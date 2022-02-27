import json

import pyproj  # type: ignore
from shapely.geometry import LineString  # type: ignore
from shapely.geometry import GeometryCollection, Point, shape  # type: ignore
from shapely.ops import transform  # type: ignore

from .globalmaptiles import GlobalMercator


class TileInPoly:
    PIXEL = 512
    WIDTH = 4096

    def __init__(self, geosjon):
        j = json.load(geosjon)
        if j.get("type") == "FeatureCollection":
            features = j["features"]
            self.polygon = GeometryCollection(
                [shape(feature["geometry"]) for feature in features]
            )
        else:
            self.polygon = shape(j)

        wgs84 = pyproj.CRS("EPSG:4326")
        wmer = pyproj.CRS("EPSG:3857")

        project = pyproj.Transformer.from_crs(wgs84, wmer, always_xy=True).transform
        self.polygon = transform(project, self.polygon)

        self.marcator = GlobalMercator(self.PIXEL)

    def is_tile_outside_poly(self, z, x, y):
        bound = self.marcator.TileBounds(x, y, z)
        bound = LineString(((bound[0], -bound[1]), (bound[2], -bound[3]))).envelope
        return not self.polygon.intersection(bound)

    def is_tile_inside_poly(self, z, x, y):
        bound = self.marcator.TileBounds(x, y, z)
        bound = LineString(((bound[0], -bound[1]), (bound[2], -bound[3]))).envelope
        return self.polygon.contains(bound)

    def point_in_poly(self, z, x, y):
        x_base, y_base = self.marcator.TileBounds(x, y, z)[0:2]
        res = self.marcator.Resolution(z)

        def is_point_in_poly(fx, fy):
            point = Point(
                x_base + fx * self.PIXEL * res / self.WIDTH,
                -(y_base + fy * self.PIXEL * res / self.WIDTH),
            )
            return self.polygon.contains(point)

        return is_point_in_poly
