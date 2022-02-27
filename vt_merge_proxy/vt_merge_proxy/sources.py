import gzip

import pymbtiles  # type: ignore
import requests
import vector_tile_base  # type: ignore


class Source:
    def tilejson(self, headers, url_params: str):
        return {}


class SourceMBTiles(Source):
    def __init__(self, mbtiles: str):
        self.src = pymbtiles.MBtiles(mbtiles)

    def tile(self, z: int, x: int, y: int, headers, url_params: str):
        y = 2 ** z - 1 - y
        tile_data = self.src.read_tile(z=z, x=x, y=y)
        if not tile_data:
            return [None, None]
        else:
            tile_data = gzip.decompress(tile_data)
            return [vector_tile_base.VectorTile(tile_data), tile_data]

    def tilejson(self, headers, url_params: str):
        return self.src.meta


class SourceXYZ(Source):
    def __init__(self, template_url: str):
        self.template_url = template_url

    def tile(self, z: int, x: int, y: int, headers, url_params: str):
        url = self.template_url.format_map({"z": z, "x": x, "y": y})
        if url_params:
            url = f"{url}?{url_params}"
        r = requests.get(url, headers=headers)
        r.raise_for_status()
        return [vector_tile_base.VectorTile(r.content), r.content]


class SourceTileJSON(SourceXYZ):
    def __init__(self, tilejson_url: str, tile_url: str = None):
        r = requests.get(tilejson_url)
        r.raise_for_status()
        self._tilejson = r.json()

        template_url = self._tilejson["tiles"][0]
        if tile_url:
            template_url = template_url[
                template_url.index("/", template_url.index("//") + 3) :
            ]
            template_url = tile_url + template_url

        super().__init__(template_url)

    def tilejson(self, headers, url_params: str):
        return self._tilejson


def sourceFactory(source) -> Source:
    if "tilejson_url" in source:
        return SourceTileJSON(
            tilejson_url=source.get("tilejson_url"), tile_url=source.get("tile_url")
        )
    elif "mbtiles" in source:
        return SourceMBTiles(mbtiles=source.get("mbtiles"))
    else:
        raise NotImplementedError(source)
