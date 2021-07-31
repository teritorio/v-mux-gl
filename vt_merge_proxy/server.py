import json

import requests
import yaml
from fastapi import FastAPI, HTTPException, Request, Response
from starlette.responses import RedirectResponse

from .merge import merge_tile, merge_tilejson
from .sources import sourceFactory
from .tile_in_poly import TileInPoly

app = FastAPI()


config = yaml.load(open("config.yaml").read(), Loader=yaml.BaseLoader)
print(config)

if not config.get("server"):
    config["server"] = {}

public_tilejson_url = config["server"].get(
    "public_tilejson_url", "http://127.0.0.1:8000"
)
public_tile_urls = config["server"].get("public_tile_urls", ["http://127.0.0.1:8000"])


@app.get("/")
async def read_root():
    return RedirectResponse(url="/styles.json")


@app.get("/styles.json")
async def styles():
    return [
        # TODO add version and name
        {"id": style_id, "url": f"{public_tilejson_url}/data/{style_id}.json"}
        for (style_id, style_conf) in config["styles"].items()
    ]


for (style_id, style_conf) in config["styles"].items():
    sources = [sourceFactory(source) for source in style_conf["sources"].values()]
    merge_layer = style_conf["merge_layer"]
    min_zoom = int(style_conf["output"]["min_zoom"])

    tile_in_poly = None
    if "polygon" in merge_layer:
        tile_in_poly = TileInPoly(open(merge_layer["polygon"]))

    layer = merge_layer["layer"]
    fields = merge_layer["fields"]
    classes = json.loads(open(merge_layer["classes"], "r").read())

    @app.get(f"/data/{style_id}/{{z}}/{{x}}/{{y}}.pbf")
    async def tile(z: int, x: int, y: int, request: Request):
        try:
            data = merge_tile(
                min_zoom,
                sources[0],
                sources[1],
                layer,
                fields,
                classes,
                z,
                x,
                y,
                headers=request.headers,
                url_params=str(request.query_params),
                tile_in_poly=tile_in_poly,
            )
            return Response(content=data, media_type="application/vnd.vector-tile")
        except requests.exceptions.HTTPError as error:
            raise HTTPException(
                status_code=error.response.status_code, detail=error.response.reason
            )

    @app.get(f"/data/{style_id}.json")
    async def tilejson(request: Request):
        try:
            style_public_tile_urls = [
                f"{public_tile_url}/data/{style_id}/{{z}}/{{x}}/{{y}}.pbf"
                for public_tile_url in public_tile_urls
            ]
            return merge_tilejson(
                style_public_tile_urls,
                sources[0],
                sources[1],
                headers=request.headers,
                url_params=str(request.query_params),
            )
        except requests.exceptions.HTTPError as error:
            raise HTTPException(
                status_code=error.response.status_code, detail=error.response.reason
            )
