"""Bind the complete frozen Table1 to the actual submission DOCX template.

Date: 2026-10-28. Deterministic descriptive formatting; no randomness or models.
Uses the original build_table1 definitions and existing Phase3 surgery summaries.
Authoring: bundled Python with lxml. Input reading: pandas/pyarrow/openpyxl;
--data-python may designate an existing data interpreter, receiving no DOCX job.
No analysis or file creation occurs on import or with no CLI arguments.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import csv
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unicodedata
import zipfile

sys.dont_write_bytecode = True


def require(ok, message):
    if not ok:
        raise ValueError('STOP: ' + message)


def aggregate_inputs(landmarks_path, surgery_path):
    """Patient-level reading stays local; return only the generated aggregate.

    This intentionally does not import or call surgery.run_surgery, Phase3,
    survival estimation, resampling, or any manuscript-building entry point.
    """
    import ast
    import pandas as pd
    from table1_demographics import build_table1, surgery_partition, N

    try:
        frame = pd.read_parquet(landmarks_path)
    except ImportError as exc:
        raise RuntimeError('Parquet input requires pyarrow in the data interpreter; '
                           'supply an existing --data-python or install the declared dependency') from exc
    if 'analysis_role' in frame:
        frame = frame.loc[frame.analysis_role.eq('DESCRIPTIVE')].copy()
    required = ['patient_id', 'landmark_year', 'age_dx', 'sex', 'race_ethnicity',
                'T_model', 'N_model', 'grade_model']
    require(set(required).issubset(frame.columns), 'missing original Table1 fields')
    require(not frame[required].isna().any().any(), 'missing required demographic/pathology fields')
    require(set(frame.landmark_year) == set(range(6)), 'L0-L5 landmark labels differ')
    require(frame.groupby('landmark_year').size().tolist() == N, 'frozen landmark counts differ')
    require(not frame.duplicated(['patient_id', 'landmark_year']).any(), 'duplicate patient/landmark rows')
    baseline_ids = set(frame.loc[frame.landmark_year.eq(0), 'patient_id'])
    require(all(set(g.patient_id).issubset(baseline_ids) for _, g in frame.groupby('landmark_year')),
            'a landmark patient is absent from L0')

    surgery_path = Path(surgery_path)
    if surgery_path.suffix.lower() == '.xlsx':
        surgery = pd.read_excel(surgery_path, sheet_name='Surgery_Code_Audit', header=4, dtype=object)
    elif surgery_path.suffix.lower() == '.csv':
        surgery = pd.read_csv(surgery_path, dtype=object, keep_default_na=False)
    else:
        raise ValueError('STOP: surgery-summary must be the actual frozen XLSX or aggregate CSV')
    require({'row_type', 'cohort', 'surgery_group', 'landmark', 'n'}.issubset(surgery.columns),
            'missing frozen surgery summary fields')
    before, old_sections = build_table1(frame)
    complete, sections = build_table1(frame, surgery)
    require(complete[:len(before)] == before, 'an original demographic/pathology cell changed')
    partition = surgery_partition(N, surgery)

    # Obtain dictionary and grouping semantics from the real, included source
    # by AST inspection. Importing that module is unnecessary and prohibited.
    source = Path(__file__).resolve().parents[1] / 'phase3_minimal/surgery_audit.py'
    tree = ast.parse(source.read_text(encoding='utf-8-sig'))
    constants = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name in ('CODE_DEFINITIONS', 'SURGERY_URL', 'OLD_URL', 'NEW_URL', 'OLD_FIELD', 'NEW_FIELD'):
                constants[name] = ast.literal_eval(node.value)
    mappings = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'dynamic_group'
                                               for t in node.targets)
                and isinstance(node.value, ast.Call) and node.value.args):
            mappings.append(ast.literal_eval(node.value.args[0]))
    require(len(mappings) == 1 and set(mappings[0].values()) == {'30/40', '60'},
            'included original surgery grouping source is ambiguous')
    require(set(constants) == {'CODE_DEFINITIONS', 'SURGERY_URL', 'OLD_URL', 'NEW_URL', 'OLD_FIELD', 'NEW_FIELD'},
            'included surgery dictionary/source constants are incomplete')
    return dict(before=before, complete=complete, old_sections=old_sections,
                section_rows=sections, partition=partition, dictionary=constants,
                original_code_mapping=mappings[0], grouping_source='phase3_minimal/surgery_audit.py',
                patient_rows_exported=False, bootstrap_executed=False)


def load_aggregate(args):
    if not args.data_python:
        return aggregate_inputs(args.landmarks, args.surgery_summary)
    executable = Path(args.data_python).expanduser().resolve(strict=True)
    require(executable.is_file(), '--data-python is not an installed executable')
    if executable == Path(sys.executable).resolve():
        return aggregate_inputs(args.landmarks, args.surgery_summary)
    command = [str(executable), '-B', '-X', 'utf8', str(Path(__file__).resolve()),
               '--aggregate-only', '--landmarks', str(args.landmarks),
               '--surgery-summary', str(args.surgery_summary)]
    process = subprocess.run(command, capture_output=True, text=True, encoding='utf-8',
                             check=False, env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
    require(process.returncode == 0, 'read-only aggregate bridge failed: ' + process.stderr.strip())
    aggregate = json.loads(process.stdout)
    require(aggregate.get('patient_rows_exported') is False
            and aggregate.get('bootstrap_executed') is False, 'invalid data bridge contract')
    return aggregate


def normalized(text):
    return ' '.join(unicodedata.normalize('NFKC', str(text)).split())


def canonical_cell(text):
    """Only typography may differ; no rounding tolerance or number replacement."""
    value = normalized(text)
    value = re.sub(r'(?<=\d),(?=\d)', '', value)
    return value.replace('\u2013', '-').replace('\u2212', '-')


def submission_template(submission_zip):
    from lxml import etree as E

    ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    with zipfile.ZipFile(submission_zip) as outer:
        matches = []
        for item in outer.infolist():
            if not item.filename.lower().endswith('.docx') or item.is_dir():
                continue
            raw = outer.read(item)
            with zipfile.ZipFile(io.BytesIO(raw)) as package:
                if 'word/document.xml' not in package.namelist():
                    continue
                root = E.fromstring(package.read('word/document.xml'))
            body = root.find('w:body', ns)
            if body is None:
                continue
            for table in body.findall('w:tbl', ns):
                cells = [[''.join(c.xpath('.//w:t/text()', namespaces=ns))
                          for c in row.findall('w:tc', ns)] for row in table.findall('w:tr', ns)]
                if cells and len(cells[0]) == 7 and normalized(cells[0][0]) == 'Characteristic':
                    matches.append((item.filename, raw, root, table, cells))
    require(len(matches) == 1, 'ZIP must contain exactly one unambiguous manuscript Table1 template')
    member, raw, root, table, cells = matches[0]
    body = root.find('w:body', ns)
    children = list(body)
    index = children.index(table)
    require(index > 0 and index + 1 < len(children), 'missing real Table1 caption/notes')
    caption, notes = children[index - 1], children[index + 1]
    caption_text = ''.join(caption.xpath('.//w:t/text()', namespaces=ns))
    notes_text = ''.join(notes.xpath('.//w:t/text()', namespaces=ns))
    require(caption.tag == '{' + ns['w'] + '}p' and re.match(r'^Table\s+1[.]', caption_text),
            'real Table1 caption was not found immediately before the table')
    require(notes.tag == '{' + ns['w'] + '}p' and notes_text.startswith('Notes:'),
            'real Table1 notes were not found immediately after the table')
    require('30/40' in notes_text and '60' in notes_text and 'margin' in notes_text.lower(),
            'surgery registration/margin-status footnote is missing')
    return dict(member=member, raw=raw, root=root, table=table, cells=cells,
                caption=caption, notes=notes, ns=ns)


def validate_complete(aggregate, template):
    generated, source = aggregate['complete'], template['cells']
    require(len(generated) == len(source) == 29 and all(len(row) == 7 for row in source),
            'complete 29-row/7-column Table1 shape differs')
    require(generated[:len(aggregate['before'])] == aggregate['before'],
            'original demographic/pathology values are not preserved')
    mismatches = []
    for i, (left, right) in enumerate(zip(generated, source)):
        for j, (value, reference) in enumerate(zip(left, right)):
            if canonical_cell(value) != canonical_cell(reference):
                mismatches.append(f'row {i + 1}, column {j + 1}: generated={value!r}; manuscript={reference!r}')
    require(not mismatches, 'generated Table1 disagrees with the manuscript; no numbers modified:\n'
            + '\n'.join(mismatches))
    require(all(canonical_cell(row[0]) != 'Unknown' for row in generated[-2:]),
            'Unknown surgery row is not allowed')
    return len(generated) * 7


def bind_generated_values(template, aggregate):
    """Bind every generated cell, retaining the reference's grouping punctuation."""
    table = deepcopy(template['table'])
    ns = template['ns']
    for i, row in enumerate(table.findall('w:tr', ns)):
        for j, cell in enumerate(row.findall('w:tc', ns)):
            value = str(aggregate['complete'][i][j])
            reference = template['cells'][i][j]
            require(canonical_cell(value) == canonical_cell(reference), 'unvalidated cell binding')
            # Reference grouping separators are a formatting choice, not a new
            # value. The complete generated table has already been reconciled.
            if re.match(r'^\d[\d,]* \(\d+\.\d\)$', value):
                count, percentage = re.fullmatch(r'(\d[\d,]*) \((\d+\.\d)\)', value).groups()
                count = int(count.replace(',', ''))
                shown = f'{count:,}' if ',' in reference.split(' ')[0] else str(count)
                value = f'{shown} ({percentage})'
            require(value == reference, 'a numeric binding would change the source presentation')
            # Once bound against every generated cell, identical visible text
            # needs no OOXML rewrite. This preserves split runs/font properties.
            if value == reference:
                continue
            nodes = cell.findall('.//w:t', ns)
            if nodes:
                nodes[0].text = value
                for other in nodes[1:]:
                    other.text = ''
            else:
                require(not value, 'nonempty template cell has no writable text node')
    return table


def three_line_borders(table, ns):
    """Local Table1 border override only; global TableGrid is untouched."""
    from lxml import etree as E

    q = lambda tag: '{' + ns['w'] + '}' + tag
    properties = table.find('w:tblPr', ns)
    require(properties is not None, 'missing original table properties')
    old = properties.find('w:tblBorders', ns)
    if old is not None:
        properties.remove(old)
    borders = E.Element(q('tblBorders'))
    later = [n for n in properties if E.QName(n).localname in
             ('shd', 'tblLayout', 'tblCellMar', 'tblLook', 'tblCaption', 'tblDescription')]
    properties.insert(list(properties).index(later[0]) if later else len(properties), borders)
    for name in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        node = E.SubElement(borders, q(name))
        node.set(q('val'), 'single' if name in ('top', 'bottom') else 'nil')
        node.set(q('sz'), '4')
        node.set(q('space'), '0')
        node.set(q('color'), 'auto')
    rows = table.findall('w:tr', ns)
    for i, row in enumerate(rows):
        for cell in row.findall('w:tc', ns):
            prop = cell.find('w:tcPr', ns)
            require(prop is not None, 'missing original cell properties')
            old = prop.find('w:tcBorders', ns)
            if old is not None:
                prop.remove(old)
            if i == 0:
                cb = E.Element(q('tcBorders'))
                later = [n for n in prop if E.QName(n).localname in
                         ('shd', 'noWrap', 'tcMar', 'textDirection', 'tcFitText', 'vAlign', 'hideMark')]
                prop.insert(list(prop).index(later[0]) if later else len(prop), cb)
                border = E.SubElement(cb, q('bottom'))
                for key, value in (('val', 'single'), ('sz', '4'), ('space', '0'), ('color', 'auto')):
                    border.set(q(key), value)
    return table


def package_document(original_bytes, xml):
    buffer = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(original_bytes)) as source:
        with zipfile.ZipFile(buffer, 'w') as output:
            for item in source.infolist():
                value = xml if item.filename == 'word/document.xml' else source.read(item)
                output.writestr(item, value)
    return buffer.getvalue()


def document_bytes(template, aggregate, standalone):
    from lxml import etree as E

    root = deepcopy(template['root'])
    ns = template['ns']
    body = root.find('w:body', ns)
    table_index = list(template['root'].find('w:body', ns)).index(template['table'])
    table = three_line_borders(bind_generated_values(template, aggregate), ns)
    if standalone:
        section = deepcopy(body.find('w:sectPr', ns))
        require(section is not None, 'missing source page geometry')
        for node in list(body):
            body.remove(node)
        body.extend([deepcopy(template['caption']), table, deepcopy(template['notes']), section])
    else:
        original = list(body)[table_index]
        body.replace(original, table)
        # No main-manuscript body node other than Table1 may change.
        a, b = deepcopy(template['root']), deepcopy(root)
        for document in (a, b):
            doc_body = document.find('w:body', ns)
            doc_body.remove(list(doc_body)[table_index])
        require(E.tostring(a, method='c14n') == E.tostring(b, method='c14n'),
                'unexpected main-manuscript change outside Table1')
    xml = E.tostring(root, xml_declaration=True, encoding='UTF-8', standalone=True)
    result = package_document(template['raw'], xml)
    with zipfile.ZipFile(io.BytesIO(template['raw'])) as before, zipfile.ZipFile(io.BytesIO(result)) as after:
        require(before.namelist() == after.namelist(), 'DOCX package parts changed')
        require(all(before.read(n) == after.read(n) for n in before.namelist() if n != 'word/document.xml'),
                'a preserve-only DOCX package part changed')
    return result


def validation_markdown(aggregate, template, checked_cells, main_requested):
    rows = ['# Table1 validation', '', 'Status: PASS', '',
            f'Submission template: `{template["member"]}`.',
            f'All {checked_cells} cells in the complete29-row/7-column table were compared against the manuscript.',
            'Original26 demographic/pathology rows are unchanged. Only the surgery section and two rows are appended.',
            'No patient records, new model, cohort reconstruction, outcome analysis or resampling was exported or executed.', '',
            '## Complete row reconciliation', '',
            '| Row | Characteristic | Original generator L0-L5 | Complete generator L0-L5 | Manuscript L0-L5 | Check |',
            '|---|---|---|---|---|---|']
    for i, row in enumerate(aggregate['complete']):
        old = '; '.join(aggregate['before'][i][1:]) if i < len(aggregate['before']) else 'Not in original generator'
        new = '; '.join(row[1:])
        source = '; '.join(template['cells'][i][1:])
        rows.append(f'| {i + 1} | {row[0]} | {old} | {new} | {source} | PASS |')
    rows.extend(['', '## Frozen surgery partition', '',
                 '| Landmark | Frozen group | n | Actual landmark denominator | Percent, one decimal | Check |',
                 '|---|---|---|---|---|---|'])
    for row in aggregate['partition']:
        rows.append(f'| L{row["landmark"]} | {row["surgery_group"]} | {row["n"]} | '
                    f'{row["denominator"]} | {row["percentage"]:.1f} | PASS |')
    rows.extend(['', 'Only12 rows with row_type=LANDMARK_ESTIMATE and cohort=Dynamic supplied these surgery counts.',
                 'At every landmark, the two groups sum exactly to the original denominator; there is no Unknown surgery category.', '',
                 '## Surgery dictionary provenance', '',
                 f'Actual included grouping source: `{aggregate["grouping_source"]}` (inspected by AST; never executed).',
                 f'Actual source mapping: `{json.dumps(aggregate["original_code_mapping"], sort_keys=True)}`.',
                 'The export does not map individual surgery codes or borrow counts from Source/Life-table cohorts.'])
    definitions = aggregate['dictionary']['CODE_DEFINITIONS']
    for code in aggregate['original_code_mapping']:
        rows.append(f'- Code {code}: {definitions[code]}')
    rows.extend([f'- Original field: {aggregate["dictionary"]["OLD_FIELD"]}.',
                 f'- [SEER surgery variables]({aggregate["dictionary"]["SURGERY_URL"]})',
                 f'- [Original old-code dictionary]({aggregate["dictionary"]["OLD_URL"]})',
                 'Dynamic-cohort diagnosis years are2004-2015; no2023 A-series mapping is introduced.',
                 'Code60 is a registry extent category, not confirmation of R0 margins or a causal surgery effect.', '',
                 '## Template and package preservation', '',
                 'The original ZIP Table1 caption, all text/value cells, column geometry, indentation, fonts, header and footnote are retained.',
                 'The real template inherits a full-grid TableGrid style. To meet the requested three-line format, only Table1 local tblPr/tcPr border overrides change: top/bottom rules and the header-bottom rule; no vertical/internal body rules.',
                 'The global styles part and every DOCX part other than word/document.xml remain byte-identical.',
                 'The standalone document keeps the actual caption/table/notes and section geometry, removing other body content.',
                 ('Main-manuscript assembly requested: every generated cell was bound and validated; only Table1 local borders may differ. Table-external XML is checked unchanged.'
                  if main_requested else 'Main-manuscript assembly not requested; the source manuscript remains untouched.'),
                 'Document output still requires external render-and-visual review before submission; structural/numeric PASS alone does not certify page layout.', ''])
    return '\n'.join(rows)


def output_targets(args):
    directory = Path(args.output_dir).expanduser().resolve(strict=True)
    require(directory.is_dir(), 'create the private output-dir before exporting')
    repository = Path(__file__).resolve().parents[1]
    require(directory != repository and repository not in directory.parents,
            'output-dir must be outside the public repository')
    # Refuse writes beneath the frozen input roots when configured. The direct
    # input files are protected too, irrespective of environment configuration.
    for name in ('GBC_FINAL_RUN_ROOT', 'GBC_PREPARATION_ROOT'):
        if os.environ.get(name):
            protected = Path(os.environ[name]).expanduser().resolve(strict=True)
            require(directory != protected and protected not in directory.parents,
                    'output-dir lies inside a frozen input root')
    targets = [directory / 'Table1.csv', directory / 'Table1.docx', directory / 'Table1_VALIDATION.md']
    if args.main_output:
        main = Path(args.main_output).expanduser()
        main = main.parent.resolve(strict=True) / main.name
        require(main.suffix.lower() == '.docx', 'main-output must be DOCX')
        require(main.parent == directory, 'main-output must use the same private output-dir')
        targets.append(main)
    inputs = {Path(p).expanduser().resolve(strict=True)
              for p in (args.landmarks, args.surgery_summary, args.submission_zip)}
    require(len(set(targets)) == len(targets), 'output filenames collide')
    require(all(not p.exists() and p not in inputs for p in targets), 'an output exists or would overwrite an input')
    return targets


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--landmarks', type=Path)
    parser.add_argument('--surgery-summary', type=Path)
    parser.add_argument('--submission-zip', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--main-output', type=Path, help='Optional complete manuscript DOCX, in output-dir')
    parser.add_argument('--data-python', type=Path, help='Existing data-only interpreter with pyarrow')
    parser.add_argument('--validate-only', action='store_true', help='Read-only whole-table comparison; no artifacts')
    parser.add_argument('--aggregate-only', action='store_true', help=argparse.SUPPRESS)
    values = sys.argv[1:] if argv is None else argv
    if not values:
        parser.print_help()
        return
    args = parser.parse_args(values)
    if not args.landmarks or not args.surgery_summary:
        parser.error('--landmarks and --surgery-summary are required')
    if args.aggregate_only:
        aggregate = aggregate_inputs(args.landmarks, args.surgery_summary)
        print(json.dumps(aggregate, ensure_ascii=True, allow_nan=False))
        return
    if not args.submission_zip:
        parser.error('--submission-zip is required')
    if not args.validate_only and not args.output_dir:
        parser.error('--output-dir is required for export')
    targets = None if args.validate_only else output_targets(args)
    aggregate = load_aggregate(args)
    template = submission_template(args.submission_zip)
    cells = validate_complete(aggregate, template)
    if args.validate_only:
        print(f'PASS: all{cells} Table1 cells reconciled; original demographic/pathology rows preserved; '
              '12 frozen surgery rows partition L0-L5. No artifacts created; no resampling executed.')
        return
    # Author only after the full patient-derived table has reconciled, so a
    # conflicting manuscript never receives silently repaired numbers.
    standalone = document_bytes(template, aggregate, standalone=True)
    main_bytes = document_bytes(template, aggregate, standalone=False) if args.main_output else None
    report = validation_markdown(aggregate, template, cells, bool(args.main_output))
    with targets[0].open('x', encoding='utf-8-sig', newline='') as handle:
        csv.writer(handle).writerows(aggregate['complete'])
    with targets[1].open('xb') as handle:
        handle.write(standalone)
    if main_bytes is not None:
        with targets[3].open('xb') as handle:
            handle.write(main_bytes)
    with targets[2].open('x', encoding='utf-8') as handle:
        handle.write(report)
    print('PASS: complete Table1 and validation exported; original inputs unchanged. Render QA is still required.')


if __name__ == '__main__':
    main()
