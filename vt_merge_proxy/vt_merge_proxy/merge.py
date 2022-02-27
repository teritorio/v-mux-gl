import copy
import random
from typing import Dict, List, Optional

import vector_tile_base  # type: ignore

from .tile_in_poly import TileInPoly


# Monkey patch
def FeatureAttributes___setitem__(self, key, value):
    if not isinstance(key, str) and not isinstance(key, bytes):
        raise TypeError("Keys must be of type str or bytes")
    self._decode_attr()
    self._attr[key] = value
    # self._encode_attr() # Disable encoding at each __setitem__()


vector_tile_base.FeatureAttributes.__setitem__ = FeatureAttributes___setitem__


def layer_extract(tile, layer_name: str):
    return next(filter(lambda layer: layer.name == layer_name, tile.layers), None)


def get_attribute(attributes, key: str, default=None):
    return default if key not in attributes else attributes[key]


def get_classes(fields, feature):
    attributes = feature.attributes
    return [get_attribute(attributes, field) for field in fields]


def match_class_list(fields, feature, classes):
    feature_class = get_classes(fields, feature)
    return any(map(lambda classs: classs == feature_class[: len(classs)], classes))


def include_feature(fields, feature, classes, point_in_poly):
    if not point_in_poly or point_in_poly(*feature.get_points()[0]):
        return match_class_list(fields, feature, classes)
    else:
        return False


def exclude_features(fields, features, classes, point_in_poly):
    if classes:
        return list(
            filter(
                lambda feature: not include_feature(
                    fields, feature, classes, point_in_poly
                ),
                features,
            )
        )
    else:
        return features


def include_features(fields, features, classes, point_in_poly):
    if classes:
        return list(
            filter(
                lambda feature: include_feature(
                    fields, feature, classes, point_in_poly
                ),
                features,
            )
        )
    else:
        return []


# FIXME hardcoded fields
def rank(features):
    grid = {}
    for f in features:
        x, y = f.get_geometry()[0]
        x = (x + 50) // 100
        y = (y + 50) // 100
        h = (x, y)
        if h not in grid:
            grid[h] = []
        grid[h].append(f)

    for _, group_features in grid.items():
        poi = sorted(
            group_features,
            key=lambda a: [
                get_attribute(a.attributes, "zoom", 18),
                get_attribute(a.attributes, "priority", 9999),
            ],
        )
        for rank, feature in enumerate(poi):
            feature.attributes["rank"] = rank  # Monkey patched to disable encoding

    return features


def build_feature(merge_tile_layer, f):
    if f.type == "point":
        feature = merge_tile_layer.add_point_feature()
        feature.add_points(f.get_geometry())
    elif f.type == "line_string":
        feature = merge_tile_layer.add_line_string_feature()
        for g in f.get_geometry():
            feature.add_line_string(g)
    elif f.type == "polygon":
        feature = merge_tile_layer.add_polygon_feature()
        for g in f.get_geometry():
            for q in g:
                feature.add_ring(q)
    elif f.type == "spline":
        feature = merge_tile_layer.add_spline_feature()
        feature.add_spline(f.get_geometry())
    else:
        raise Exception(f.type)

    feature.id = f.id if f.id is not None else random.randrange(2 ** 32)
    # FIXME decode/encode to be done only if changed
    f.attributes._decode_attr()
    # FIXME Attribut re-encoding : slowest step
    # https://github.com/mapbox/vector-tile-base/blob/master/vector_tile_base/engine.py#L251
    feature.attributes = f.attributes._attr


def build_tile(model, layer_features: Dict[str, List[object]]):
    disabled_layers = layer_features.keys()
    for layer in model.layers:
        if layer.name in disabled_layers:
            layer.name = "_" + layer.name
            break

    for layer_name, features in layer_features.items():
        layer = model.add_layer(layer_name)
        for feature in features:
            build_feature(layer, feature)

    return model


def merge_tile(
    min_zoom,
    full,
    partial,
    layers,
    z: int,
    x: int,
    y: int,
    headers,
    url_params: str,
    tile_in_poly: Optional[TileInPoly],
):
    full_tile, full_raw_tile = full.tile(
        z=z, x=x, y=y, headers=headers, url_params=url_params
    )
    if z < min_zoom:
        return full_raw_tile

    if tile_in_poly and tile_in_poly.is_tile_outside_poly(z, x, y):
        return full_raw_tile

    if tile_in_poly and tile_in_poly.is_tile_inside_poly(z, x, y):
        tile_in_poly = None  # Disable geo filter

    partial_tile, partial_raw_tile = partial.tile(
        z=z, x=x, y=y, headers=headers, url_params=url_params
    )

    full_features = {}
    full_features_same = {}
    partial_features = {}
    for layer, layer_config in layers.items():
        if full_tile:
            full_tile_layer = layer_extract(full_tile, layer)
            if full_tile_layer:
                if layer_config.fields:
                    full_features[layer] = exclude_features(
                        layer_config.fields,
                        full_tile_layer.features,
                        layer_config.classes,
                        tile_in_poly and tile_in_poly.point_in_poly(z, x, y),
                    )
                    full_features_same[layer] = len(full_features[layer]) == len(
                        full_tile_layer.features
                    )
                else:
                    full_features[layer] = full_tile_layer.features
                    full_features_same[layer] = True
            else:
                full_features[layer] = []

        if partial_tile:
            partial_tile_layer = layer_extract(partial_tile, layer)
            if partial_tile_layer:
                if layer_config.fields:
                    partial_features[layer] = include_features(
                        layer_config.fields,
                        partial_tile_layer.features,
                        layer_config.classes,
                        tile_in_poly and tile_in_poly.point_in_poly(z, x, y),
                    )
                else:
                    partial_features[layer] = partial_tile_layer.features
            else:
                partial_features[layer] = []

    if len(list(filter(lambda f: f, partial_features))) == 0:
        if full_tile is None:
            return None
        elif len(full_features) == 0:
            return full_raw_tile
        elif all(full_features_same.values()):
            return full_raw_tile
        else:
            merge_features = build_tile(full_tile, full_features)
            return merge_features.serialize()

    else:
        if full_tile is None:
            return partial_raw_tile
        else:
            features = {}
            for layer in set(
                list(full_features.keys()) + list(partial_features.keys())
            ):
                if len(full_features.get(layer, [])) > 0:
                    features[layer] = rank(
                        full_features[layer] + partial_features[layer]
                    )
                else:
                    features[layer] = partial_features[layer]

            merge_features = build_tile(full_tile, features)
            return merge_features.serialize()


def merge_tilejson(
    public_tile_urls, full, partial, layers: List[str], headers, url_params: str
):
    full_tilejson = full.tilejson(headers, url_params)
    partial_tilejson = partial.tilejson(headers, url_params)

    partial_attribution = partial_tilejson.get("attribution", "")
    full_attribution = full_tilejson.get("attribution", "")
    attributions = partial_attribution + "," + full_attribution
    attributions = attributions.replace("/a> <a", "/a>,<a").split(",")
    attributions = set(
        [attribution.strip() for attribution in attributions if attribution.strip()]
    )
    attributions = " ".join(attributions)

    tilejson = copy.deepcopy(full_tilejson)
    tilejson["attribution"] = attributions

    if public_tile_urls:
        tilejson["tiles"] = public_tile_urls

    if url_params:
        tilejson["tiles"] = [url + f"?{url_params}" for url in public_tile_urls]

    for layer in layers:
        if "vector_layers" in full_tilejson and not any(
            filter(
                lambda l: l["id"] == layer,  # type: ignore
                full_tilejson["vector_layers"],  # type: ignore
            )
        ):
            if "vector_layers" in partial_tilejson:
                partial_layer = next(
                    filter(
                        lambda l: l["id"] == layer, partial_tilejson["vector_layers"]
                    )
                )
                tilejson["vector_layers"].append(partial_layer)
            else:
                tilejson["vector_layers"].append({"id": layer})

    return tilejson
