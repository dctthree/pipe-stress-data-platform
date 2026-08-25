"""Small streaming XLSX reader that ignores unreliable worksheet dimension hints."""

from __future__ import annotations

import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _column_number(cell_ref: str) -> int:
    match = re.match(r"([A-Z]+)", cell_ref)
    if not match:
        return 0
    number = 0
    for char in match.group(1):
        number = number * 26 + ord(char) - 64
    return number


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    strings: list[str] = []
    with archive.open("xl/sharedStrings.xml") as stream:
        for _, element in ET.iterparse(stream, events=("end",)):
            if _local(element.tag) == "si":
                strings.append("".join(node.text or "" for node in element.iter() if _local(node.tag) == "t"))
                element.clear()
    return strings


def _sheet_paths(archive: zipfile.ZipFile) -> list[tuple[str, str]]:
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {
        relationship.attrib["Id"]: relationship.attrib["Target"]
        for relationship in relationships.findall(f"{{{PKG_REL_NS}}}Relationship")
    }
    result: list[tuple[str, str]] = []
    for sheet in workbook.findall(f".//{{{MAIN_NS}}}sheet"):
        relationship_id = sheet.attrib[f"{{{REL_NS}}}id"]
        target = targets[relationship_id].replace("\\", "/")
        if target.startswith("/"):
            target = target.lstrip("/")
        elif not target.startswith("xl/"):
            target = "xl/" + target
        result.append((sheet.attrib["name"], target))
    return result


def _cell_value(cell: ET.Element, shared: list[str]):
    cell_type = cell.attrib.get("t", "n")
    value_node = next((node for node in cell if _local(node.tag) == "v"), None)
    if cell_type == "inlineStr":
        return "".join(node.text or "" for node in cell.iter() if _local(node.tag) == "t")
    if value_node is None or value_node.text is None:
        return None
    raw = value_node.text
    if cell_type == "s":
        return shared[int(raw)]
    if cell_type == "b":
        return raw == "1"
    if cell_type in {"str", "e"}:
        return raw
    try:
        value = float(raw)
        return int(value) if value.is_integer() else value
    except ValueError:
        return raw


def read_sheet_rows(path: Path, preferred_sheet: str | None = "Sheet1") -> tuple[str, list[list]]:
    with zipfile.ZipFile(path) as archive:
        shared = _shared_strings(archive)
        sheets = _sheet_paths(archive)
        selected = next((item for item in sheets if item[0] == preferred_sheet), None) if preferred_sheet else None
        if selected is None:
            selected = sheets[0]
        sheet_name, xml_path = selected
        sparse_rows: list[tuple[int, dict[int, object]]] = []
        max_column = 0
        with archive.open(xml_path) as stream:
            for _, element in ET.iterparse(stream, events=("end",)):
                if _local(element.tag) != "row":
                    continue
                row_number = int(element.attrib.get("r", len(sparse_rows) + 1))
                values: dict[int, object] = {}
                for cell in element:
                    if _local(cell.tag) != "c":
                        continue
                    column = _column_number(cell.attrib.get("r", ""))
                    max_column = max(max_column, column)
                    value = _cell_value(cell, shared)
                    if value is not None:
                        values[column] = value
                sparse_rows.append((row_number, values))
                element.clear()
    max_row = max((row for row, _ in sparse_rows), default=0)
    dense = [[None] * max_column for _ in range(max_row)]
    for row_number, values in sparse_rows:
        for column, value in values.items():
            dense[row_number - 1][column - 1] = value
    return sheet_name, dense

