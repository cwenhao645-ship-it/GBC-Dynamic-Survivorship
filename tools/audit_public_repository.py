"""Read-only public-code release guard. Never imports analysis entry points.

Default: tracked files plus non-ignored untracked files. --staged scans actual
index blobs (not worktree copies); --history additionally scans every reachable
commit tree. Findings contain paths/rules/line numbers, never matched contents.
Static dependency checks are deliberately incomplete; dynamic paths are REVIEW.
"""
from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

sys.dont_write_bytecode = True

SAFE_CSV = {"environment/package_versions.csv"}
TEXT_SUFFIX = {".py", ".r", ".mjs", ".js", ".md", ".txt", ".yml", ".yaml",
               ".json", ".cff", ".ps1", ".bat", ".sh", ".toml", ".lock", ".csv"}
DENIED_SUFFIX = {".parquet", ".rds", ".rda", ".rdata", ".feather", ".arrow",
                 ".pkl", ".pickle", ".joblib", ".sav", ".dta", ".sas7bdat",
                 ".dic", ".fst", ".h5", ".hdf5", ".sqlite", ".db", ".npz",
                 ".npy", ".onnx", ".pt", ".pth", ".zip", ".rar", ".7z",
                 ".gz", ".tar", ".xlsx", ".xls", ".pdf", ".docx", ".pem", ".key"}
RULES = {
    "GITHUB_TOKEN": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
    "OPENAI_KEY": re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b"),
    "AWS_ACCESS_KEY": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "PRIVATE_KEY_BLOCK": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "URL_CREDENTIAL": re.compile(r"https?://[^\s/:@]{2,}:[^\s/@]{6,}@", re.I),
}
PERSONAL_PATH = re.compile(r"[Cc]:[\\/]+Users[\\/]+([^\\/\s\"'<>]+)", re.I)
SECRET_ASSIGN = re.compile(
    r"\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|client[_-]?secret)"
    r"\s*[:=]\s*[\"']([^\"'\r\n]{16,})[\"']", re.I)
PLACEHOLDER = re.compile(r"(?:example|placeholder|your[_ -]|replace|dummy|redacted|<|\$\{|\.\.\.)", re.I)
CODE_EXT = (".R", ".r", ".py", ".mjs", ".js")
MAX_BYTES = 32 * 1024 * 1024


@dataclass(frozen=True)
class Finding:
    severity: str
    path: str
    rule: str
    line: int = 0


class Audit:
    def __init__(self, root: Path):
        self.root = root
        self.findings: set[Finding] = set()
        self.python_count = 0
        self.scanned = 0
        self.dependencies = 0
        self.external_imports: set[str] = set()

    def add(self, severity: str, path: str, rule: str, line: int = 0):
        self.findings.add(Finding(severity, path, rule, line))

    def git(self, *args: str) -> bytes:
        p = subprocess.run(["git", "-C", str(self.root), *args],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if p.returncode:
            raise RuntimeError("git command failed: " + args[0])
        return p.stdout

    def index(self):
        entries = {}
        for record in self.git("ls-files", "--stage", "-z").split(b"\0"):
            if not record:
                continue
            metadata, raw_path = record.split(b"\t", 1)
            mode, oid, stage = metadata.decode("ascii").split()
            path = raw_path.decode("utf-8", "surrogateescape")
            if stage != "0":
                self.add("FAIL", path, "UNMERGED_INDEX")
                continue
            if mode == "160000":
                self.add("FAIL", path, "SUBMODULE_NOT_AUDITED")
                continue
            if mode == "120000":
                self.add("FAIL", path, "SYMLINK_NOT_ALLOWED")
            entries[path] = self.git("cat-file", "blob", oid)
        return entries

    def worktree(self):
        entries = {}
        names = self.git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
        for raw in names.split(b"\0"):
            if not raw:
                continue
            name = raw.decode("utf-8", "surrogateescape")
            path = self.root / name
            if not path.exists():  # A pending tracked deletion is not an upload.
                continue
            if path.is_symlink():
                self.add("FAIL", name, "SYMLINK_NOT_ALLOWED")
                continue
            if not path.is_file():
                self.add("REVIEW", name, "NONREGULAR_PATH")
                continue
            if path.stat().st_size > MAX_BYTES:
                self.add("FAIL", name, "OVERSIZE_NOT_CONTENT_AUDITED")
                continue
            entries[name] = path.read_bytes()
        return entries

    def scan(self, path: str, blob: bytes, historical=False):
        self.scanned += 1
        normalized = path.replace("\\", "/")
        label = ("history:" if historical else "") + normalized
        suffix = PurePosixPath(normalized).suffix.lower()
        base = PurePosixPath(normalized).name.lower()
        parts = {p.lower() for p in PurePosixPath(normalized).parts}
        if suffix in DENIED_SUFFIX:
            self.add("FAIL", label, "RESTRICTED_DATA_OR_UNAPPROVED_BINARY_TYPE")
        if suffix in {".csv", ".tsv"} and normalized not in SAFE_CSV:
            self.add("FAIL", label, "TABULAR_DATA_NOT_EXPLICITLY_ALLOWLISTED")
        if base == ".env" or (base.startswith(".env.") and not base.endswith(".example")):
            self.add("FAIL", label, "LOCAL_SECRET_CONFIGURATION")
        if parts & {"data_raw", "data_clean", "__pycache__", ".cache"}:
            self.add("FAIL", label, "RESTRICTED_DATA_OR_CACHE_DIRECTORY")
        if suffix == ".pyc":
            self.add("FAIL", label, "PYTHON_CACHE")
        if len(blob) > MAX_BYTES:
            self.add("FAIL", label, "OVERSIZE_NOT_CONTENT_AUDITED")
            return None
        try:
            text = blob.decode("utf-8-sig")
        except UnicodeDecodeError:
            if suffix in TEXT_SUFFIX or suffix not in DENIED_SUFFIX:
                self.add("FAIL", label, "NON_UTF8_OR_UNAUDITED_BINARY")
            return None
        if "\x00" in text:
            self.add("FAIL", label, "BINARY_CONTENT_IN_TEXT_PATH")
            return None
        for number, line in enumerate(text.splitlines(), 1):
            for rule, pattern in RULES.items():
                if pattern.search(line):
                    self.add("FAIL", label, rule, number)
            if PERSONAL_PATH.search(line):
                self.add("FAIL", label, "PERSONAL_WINDOWS_HOME_PATH", number)
            for match in SECRET_ASSIGN.finditer(line):
                value = match.group(1)
                if not PLACEHOLDER.search(value) and len(set(value)) >= 8:
                    self.add("FAIL", label, "HIGH_SIGNAL_SECRET_ASSIGNMENT", number)
        if suffix == ".py":
            self.python_count += 1
            try:
                return ast.parse(text, filename=normalized), text
            except SyntaxError as error:
                self.add("FAIL", label, "PYTHON_SYNTAX", error.lineno or 0)
        return None, text

    def dependency(self, source: str, reference: str, paths: set[str], line: int):
        self.dependencies += 1
        value = reference.replace("\\", "/")
        if re.match(r"^(?:[A-Za-z]:/|/|https?://|<|\$)", value):
            self.add("REVIEW", source, "EXTERNAL_OR_DYNAMIC_CODE_DEPENDENCY", line)
            return
        parent = PurePosixPath(source).parent
        candidates = {value, str(parent / value)}
        # Lexically collapse '..'; no filesystem access is needed for staged checks.
        def normalize(name):
            parts = []
            for part in PurePosixPath(name).parts:
                if part == ".." and parts:
                    parts.pop()
                elif part != ".":
                    parts.append(part)
            return "/".join(parts)
        candidates = {normalize(p) for p in candidates}
        if candidates & paths:
            return
        # Unknown HERE/root variables cannot establish a full static closure.
        tail_matches = [p for p in paths if p.endswith("/" + value)]
        if len(tail_matches) == 1:
            self.add("REVIEW", source, "DEPENDENCY_LOCATION_REQUIRES_RUNTIME_ROOT_REVIEW", line)
            return
        severity = "REVIEW" if source.startswith("legacy/") else "FAIL"
        self.add(severity, source, "MISSING_LOCAL_CODE_DEPENDENCY", line)

    def code_dependencies(self, entries: dict[str, bytes], parsed):
        paths = set(entries)
        local_modules = {PurePosixPath(p).stem for p in paths if p.endswith(".py")}
        stdlib = set(getattr(sys, "stdlib_module_names", ())) | set(sys.builtin_module_names)
        for path, (tree, text) in parsed.items():
            if tree is not None:
                for node in ast.walk(tree):
                    if isinstance(node, ast.Import):
                        for alias in node.names:
                            first = alias.name.split(".")[0]
                            if first not in stdlib and first not in local_modules:
                                self.external_imports.add(first)
                    elif isinstance(node, ast.ImportFrom):
                        if node.level:
                            parent = PurePosixPath(path).parent
                            for _ in range(node.level - 1):
                                parent = parent.parent
                            module = (node.module or "").replace(".", "/")
                            refs = [str(parent / module) + ".py", str(parent / module / "__init__.py")]
                            self.dependencies += 1
                            if not set(refs) & paths:
                                self.add("FAIL", path, "MISSING_RELATIVE_PYTHON_IMPORT", node.lineno)
                        elif node.module:
                            first = node.module.split(".")[0]
                            if first == "scripts":
                                module = node.module.replace(".", "/")
                                refs = {module + ".py", "python/" + module + ".py",
                                        module + "/__init__.py", "python/" + module + "/__init__.py"}
                                self.dependencies += 1
                                if not refs & paths:
                                    self.add("FAIL", path, "MISSING_PUBLIC_PYTHON_SCRIPTS_IMPORT", node.lineno)
                            elif first not in stdlib and first not in local_modules:
                                self.external_imports.add(first)
                    elif isinstance(node, ast.Call):
                        func = ast.unparse(node.func)
                        if func.endswith(("load_local", "spec_from_file_location", "run_path")):
                            constants = [n.value for n in ast.walk(node)
                                         if isinstance(n, ast.Constant) and isinstance(n.value, str)]
                            refs = [x for x in constants if x.endswith(CODE_EXT)]
                            if refs:
                                # pathlib root/'dir'/'script.py' chains are reconstructed.
                                expr = node.args[0] if node.args else None
                                if isinstance(expr, ast.BinOp):
                                    def path_parts(value):
                                        if isinstance(value, ast.BinOp) and isinstance(value.op, ast.Div):
                                            return path_parts(value.left) + path_parts(value.right)
                                        if isinstance(value, ast.Constant) and isinstance(value.value, str):
                                            return [value.value]
                                        return []
                                    refs = ["/".join(path_parts(expr))]
                                for ref in refs:
                                    self.dependency(path, ref, paths, node.lineno)
                            else:
                                self.add("REVIEW", path, "DYNAMIC_PYTHON_CODE_LOADER", node.lineno)
            if path.lower().endswith(".r"):
                # A conservative inventory, NOT an R parser. R parse() is a separate gate.
                for match in re.finditer(r"(?<![\w.])(?:sys\.)?source\s*\(", text):
                    line = text.count("\n", 0, match.start()) + 1
                    end = min(len(text), match.end() + 500)
                    chunk = text[match.end():end].split("\n", 1)[0]
                    if text[text.rfind("\n", 0, match.start()) + 1:match.start()].lstrip().startswith("#"):
                        continue
                    strings = re.findall(r"[\"']([^\"']+)[\"']", chunk)
                    refs = [x for x in strings if x.endswith(CODE_EXT)]
                    if refs:
                        ref = refs[0]
                        if "file.path(" in chunk and strings.index(ref) > 0 and "/" not in ref and "Sys.getenv(" not in chunk:
                            prefix = strings[:strings.index(ref)]
                            if all("/" not in s and "." not in s for s in prefix):
                                ref = "/".join(prefix + [ref])
                        self.dependency(path, ref, paths, line)
                    else:
                        self.add("REVIEW", path, "DYNAMIC_R_SOURCE_REQUIRES_MANUAL_CLOSURE_REVIEW", line)
            if path.endswith((".mjs", ".js")):
                for match in re.finditer(r"(?:from\s*|import\s*\(|require\s*\()\s*[\"']([^\"']+)[\"']", text):
                    ref = match.group(1)
                    if ref.startswith("."):
                        self.dependency(path, ref, paths, text.count("\n", 0, match.start()) + 1)
        # Maintained compute-only entry contracts supplement the conservative
        # source/import inventory. These are PUBLIC dependencies actually called
        # by the current entries, not the original private workbook/PDF backend.
        # They are not a claim that arbitrary dynamic code can be fully resolved.
        required = {
            "gbc_transfer_gate/phase2/run_phase2.py": [
                "gbc_transfer_gate/phase2/phase2_lifetable.R",
                "python/scripts/stage1_burden.py", "scripts/current_kernels/lifetable_core.R"],
            "phase3_minimal/run_phase3.R": [
                "phase3_minimal/phase3_data.py", "phase3_minimal/unified_cohort.R",
                "phase3_minimal/surgery_audit.py", "gbc_transfer_gate/phase2/phase2.py",
                "python/scripts/stage1_burden.py", "scripts/current_kernels/public_config.R",
                "scripts/current_kernels/cause_specific.R", "scripts/current_kernels/lifetable_core.R"],
            "phase3_l0_ph_check/run_L0_PH_check.R": [
                "phase3_l0_ph_check/L0_model_core.R", "phase3_minimal/run_phase3.R",
                "scripts/current_kernels/public_config.R", "scripts/current_kernels/cause_specific.R"],
        }
        for entry, dependencies in required.items():
            if entry in paths:
                for ref in dependencies:
                    if ref not in paths:
                        self.add("FAIL", ref, "CURRENT_COMPUTE_DEPENDENCY_MISSING")

    def history(self):
        seen = set()
        commits = self.git("rev-list", "--all").decode("ascii").split()
        for commit in commits:
            for record in self.git("ls-tree", "-r", "-z", "--full-tree", commit).split(b"\0"):
                if not record:
                    continue
                meta, raw_path = record.split(b"\t", 1)
                mode, kind, oid = meta.decode("ascii").split()
                path = raw_path.decode("utf-8", "surrogateescape")
                if (oid, path) in seen:
                    continue
                seen.add((oid, path))
                if kind != "blob":
                    self.add("FAIL", "history:" + path, "HISTORY_NON_BLOB_NOT_AUDITED")
                    continue
                if mode == "120000":
                    self.add("FAIL", "history:" + path, "HISTORY_SYMLINK")
                self.scan(path, self.git("cat-file", "blob", oid), historical=True)
        print(f"History commits inspected: {len(commits)}; unique path/blob pairs: {len(seen)}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--staged", action="store_true", help="Scan entire index, not only changed paths.")
    parser.add_argument("--history", action="store_true", help="Also scan every reachable commit blob.")
    args = parser.parse_args(argv)
    audit = Audit(args.root.resolve())
    try:
        entries = audit.index() if args.staged else audit.worktree()
        parsed = {}
        for path, blob in entries.items():
            result = audit.scan(path, blob)
            if result is not None and path.lower().endswith((".py", ".r", ".mjs", ".js")):
                parsed[path] = result
        audit.code_dependencies(entries, parsed)
        if args.history:
            audit.history()
    except (OSError, RuntimeError, ValueError) as error:
        print("FAIL . AUDITOR_EXECUTION_ERROR (details intentionally omitted)")
        print("Exception type:", type(error).__name__)
        return 2
    for item in sorted(audit.findings, key=lambda f: (f.severity, f.path, f.line, f.rule)):
        print(f"{item.severity} {item.path}:{item.line} {item.rule}")
    failed = sum(f.severity == "FAIL" for f in audit.findings)
    review = sum(f.severity == "REVIEW" for f in audit.findings)
    print(f"Scope: {'INDEX BLOBS' if args.staged else 'WORKTREE'}; files/blobs={audit.scanned}; "
          f"Python AST parses={audit.python_count}; dependency references={audit.dependencies}")
    print("External Python import names (not imported or version-checked):", ", ".join(sorted(audit.external_imports)) or "none")
    print(f"FAIL={failed}; MANUAL_REVIEW={review}")
    print("LIMITATION: no R/JavaScript execution; dynamic source/runtime-generated code and external private inputs require manual review.")
    print("LIMITATION: pattern checks cannot prove absence of all secrets or patient data; review staged diffs and data licences separately.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
