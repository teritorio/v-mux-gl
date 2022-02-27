from typing import Any, Dict

import requests
from mergedeep import merge


class StyleGL:
    def __init__(self, url: str, overwrite: Dict[str, Any] = None):
        r = requests.get(url)
        r.raise_for_status()
        self._gljson = r.json()

        if overwrite:
            self._gljson = merge(self._gljson, overwrite)

    def json(self):
        return self._gljson

    def insert_layer(self, layer, before=None):
        index, _ = next(
            filter(lambda il: il[1]["id"] == before, enumerate(self._gljson["layers"])),
            (None, None),
        )
        if index:
            self._gljson["layers"].insert(index, layer)
        else:
            self._gljson["layers"].append(layer)
