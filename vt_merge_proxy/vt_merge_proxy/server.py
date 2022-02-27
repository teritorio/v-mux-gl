import json
import os
from collections import defaultdict
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import requests
import yaml
from fastapi import FastAPI, Header, HTTPException, Request, Response
from starlette.responses import RedirectResponse

from .merge import merge_tile, merge_tilejson
from .sources import Source, sourceFactory
from .style import StyleGL
from .tile_in_poly import TileInPoly

app = FastAPI()


config = yaml.load(
    open(os.environ.get("CONFIG", "config.yaml")).read(), Loader=yaml.UnsafeLoader
)
print(config)

if not config.get("server"):
    config["server"] = {}

public_base_path = config["server"].get("public_base_path") or ""
public_tile_url_prefixes = config["server"].get("public_tile_url_prefixes", [])


config_by_host: Dict[str, Dict[str, Any]] = defaultdict(dict)
for (config_id, config_source) in config["sources"].items():
    for host in config_source["hosts"]:
        config_by_host[host][config_id] = config_source

style_by_host: Dict[str, Dict[str, Any]] = defaultdict(dict)
for (config_id, config_source) in config["sources"].items():
    for host in config_source["hosts"]:
        for (style_id, style_config) in (config_source.get("styles") or {}).items():
            style_by_host[host][style_id] = {
                "config_id": config_id,
                "style_config": style_config,
            }


@app.get("/")
async def read_root():
    return RedirectResponse(url="/data.json")


def public_host(request: Request):
    forwarded = request.headers.get("Forwarded")
    if forwarded:
        for f in forwarded.split(",")[0].split(";"):
            k, v = f.split("=")
            if k == "host":
                return v.split(":")[0]
    return request.url.hostname


def public_url(request: Request, host_prefix=""):
    d = {
        "proto": None,
        "host": None,
        "port": None,
    }

    try:
        forwarded = request.headers.get("Forwarded")
        for f in forwarded.split(",")[0].split(";"):
            k, v = f.split("=")
            d[k] = v
    except Exception:
        pass
    finally:
        proto = d["proto"] or request.url.scheme or "http"
        host = d["host"] or request.url.hostname or "localhost"
        port = d["port"] or request.url.port or ""
        if port:
            port = f":{port}"
        return f"{proto}://{host_prefix}{host}{port}"


@app.get("/data.json")
async def data(request: Request):
    host = public_host(request)
    if host not in config_by_host:
        raise HTTPException(status_code=404)

    return [
        {
            "id": id,
            "url": public_url(request)
            + public_base_path
            + app.url_path_for("tilejson", data_id=id),
        }
        for (id, conf) in config_by_host[host].items()
    ]


@dataclass
class LayerConfig(object):
    fields: List[str]
    classes: List


@dataclass
class MergeConfig(object):
    sources: List[Source]
    min_zoom: int
    tile_in_poly: Optional[TileInPoly]
    layers: Dict[str, LayerConfig]


merge_config: Dict[str, Dict[str, Any]] = defaultdict(dict)
for (host, source_id_confs) in config_by_host.items():
    for (source_id, source_conf) in source_id_confs.items():
        tile_in_poly = None
        if "polygon" in source_conf:
            tile_in_poly = TileInPoly(open(source_conf["polygon"]))

        merge_config[host][source_id] = MergeConfig(
            sources=[
                sourceFactory(source) for source in source_conf["sources"].values()
            ],
            min_zoom=int(source_conf["output"]["min_zoom"]),
            tile_in_poly=tile_in_poly,
            layers={
                layer: LayerConfig(
                    fields=merge_layer and merge_layer.get("fields"),
                    classes=merge_layer
                    and merge_layer.get("classes")
                    and json.loads(open(merge_layer["classes"], "r").read()),
                )
                for layer, merge_layer in source_conf["merge_layers"].items()
            },
        )


@app.get("/data/{data_id}/{z}/{x}/{y}.pbf")
async def tile(data_id: str, z: int, x: int, y: int, request: Request):
    try:
        host = public_host(request)
        if host not in config_by_host:
            raise HTTPException(status_code=404)

        mc = merge_config[host][data_id]
        data = merge_tile(
            mc.min_zoom,
            mc.sources[0],
            mc.sources[1],
            mc.layers,
            z,
            x,
            y,
            headers=request.headers,
            url_params=str(request.query_params),
            tile_in_poly=mc.tile_in_poly,
        )
        return Response(content=data, media_type="application/vnd.vector-tile")
    except requests.exceptions.HTTPError as error:
        raise HTTPException(
            status_code=error.response.status_code, detail=error.response.reason
        )


@app.get("/data/{data_id}.json")
async def tilejson(data_id: str, request: Request):
    host = public_host(request)
    if host not in config_by_host:
        raise HTTPException(status_code=404)

    mc = merge_config.get(host) and merge_config[host].get(data_id)
    if not mc:
        raise HTTPException(status_code=404)

    try:
        path = f"{public_base_path}/data/{data_id}/{{z}}/{{x}}/{{y}}.pbf"
        if not public_tile_url_prefixes:
            data_public_tile_urls = [public_url(request) + path]
        else:
            data_public_tile_urls = [
                public_url(request, host_prefix=public_tile_url_prefixe) + path
                for public_tile_url_prefixe in public_tile_url_prefixes
            ]

        return merge_tilejson(
            data_public_tile_urls,
            mc.sources[0],
            mc.sources[1],
            mc.layers.keys(),
            headers=request.headers,
            url_params=str(request.query_params),
        )
    except requests.exceptions.HTTPError as error:
        raise HTTPException(
            status_code=error.response.status_code, detail=error.response.reason
        )


@app.get("/styles.json")
async def styles(request: Request):
    host = public_host(request)
    if host not in config_by_host:
        raise HTTPException(status_code=404)

    return [
        # TODO add version and name
        {
            "id": id,
            "url": public_url(request)
            + public_base_path
            + app.url_path_for("style", style_id=id),
        }
        for id in style_by_host[host].keys()
    ]


@app.get("/styles/{style_id}/style.json")
async def style(style_id: str, request: Request):
    host = public_host(request)
    if host not in config_by_host:
        raise HTTPException(status_code=404)

    config_id_style = style_by_host.get(host) and style_by_host[host].get(style_id)
    if not config_id_style:
        raise HTTPException(status_code=404)

    id = config_id_style["config_id"]
    style_config = config_id_style["style_config"]

    style_gl = StyleGL(
        url=style_config["url"],
        overwrite={
            "sources": {
                style_config["merged_source"]: {
                    "type": "vector",
                    "url": public_url(request)
                    + public_base_path
                    + app.url_path_for("tilejson", data_id=id)
                    + "?"
                    + str(request.query_params),
                }
            }
        }
        if style_config.get("merged_source")
        else {},
    )

    for layer in style_config.get("layers") or []:
        insert_before_id = layer.get("insert_before_id")
        style_gl.insert_layer(layer["layer"], before=insert_before_id)

    return style_gl.json()
