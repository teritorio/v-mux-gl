import difflib
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, cast

import requests
from mergedeep import merge as mergedeep


class Layer(Dict):
    pass


def layer_index(layers: List[Layer], layer_id: str) -> Optional[int]:
    index, _ = next(
        filter(lambda i_layer: i_layer[1]["id"] == layer_id, enumerate(layers)),
        (None, None),
    )
    return index


@dataclass
class StyleGLLayersPatch:
    delete: List[str] = field(default_factory=list)
    edited: List[Layer] = field(default_factory=list)
    add: List[Layer] = field(default_factory=list)

    def __bool__(self):
        return bool(self.delete or self.edited or self.add)

    @staticmethod
    def layers_amend(layers: List[Layer], merges: List[Layer]):
        append = []
        for merge in merges:
            index = layer_index(layers, merge["id"])
            if index is not None:
                layers[index].update(merge)
            else:
                append.append(merge)
        layers += append
        return layers

    def amend(self, merge: "StyleGLLayersPatch") -> "StyleGLLayersPatch":
        print("amend", merge)
        self.delete += merge.delete
        self.edited = self.layers_amend(self.edited, merge.edited)
        self.add = self.layers_amend(self.add, merge.add)
        print(self.add)
        return self


class StyleGL:
    def __init__(self, url: str, overwrite: Optional[Dict[str, Any]] = None):
        r = requests.get(url)
        r.raise_for_status()
        self._gljson = r.json()

        if overwrite:
            self._gljson = mergedeep(self._gljson, overwrite)

    def json(self):
        return self._gljson

    def layers(self) -> List[Layer]:
        return self.json()["layers"]

    def insert_sprite(self, sprite: str):
        self.json()["sprite"] = sprite

    def insert_layer(self, layer, before=None):
        index = layer_index(self.layers(), before)
        if index:
            self.layers().insert(index, layer)
        else:
            self.layers().append(layer)

    def layer_ids(self) -> List[str]:
        return list(map(lambda layer: layer["id"], self.layers()))

    def layers_diff(self, other) -> StyleGLLayersPatch:
        diff_iter = difflib.unified_diff(
            self.layer_ids(), other.layer_ids(), lineterm="", n=0
        )
        diff_iter = filter(lambda line: line[0:2] not in ["@@", "--", "++"], diff_iter)
        diff = list(diff_iter)

        deleted_layer_ids = list(
            map(lambda line: line[1:], filter(lambda line: line[0] == "-", diff))
        )
        add_layer_ids = list(
            map(lambda line: line[1:], filter(lambda line: line[0] == "+", diff))
        )

        other_map = {layer["id"]: layer for layer in other.layers()}
        added_layers: List[Layer] = []
        for layer_id in reversed(add_layer_ids):
            index = layer_index(other.layers(), layer_id)
            insert_before_id = other.layers()[index + 1]["id"] if index else None
            other_map[layer_id]["insert_before_id"] = insert_before_id
            added_layers.append(other_map[layer_id])

        conserved_layers_ids = (
            set(other.layer_ids()) - set(deleted_layer_ids) - set(add_layer_ids)
        )

        self_map = {layer["id"]: layer for layer in self.layers()}
        editer_layer_ids: List[str] = list(
            filter(
                lambda layer_id: self_map[layer_id] != other_map[layer_id],
                conserved_layers_ids,
            )
        )

        return StyleGLLayersPatch(
            delete=deleted_layer_ids,
            edited=list(map(lambda layer_id: other_map[layer_id], editer_layer_ids)),
            add=added_layers,
        )

    def apply_patch(self, patch: StyleGLLayersPatch):
        all_layers_ids = patch.delete + list(
            map(lambda layer: layer["id"], patch.add + patch.edited)
        )
        self._gljson["layers"] = list(
            filter(lambda layer: layer["id"] not in all_layers_ids, self.layers())
        )
        edited_map = {layer["id"]: layer for layer in patch.edited}
        self._gljson["layers"] = list(
            map(lambda layer: edited_map.get(layer["id"], layer), self.layers())
        )

        for layer in patch.add:
            insert_before_id = layer.pop("insert_before_id", None)
            self.insert_layer(layer, before=insert_before_id)

        return self
