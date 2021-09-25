#!/usr/bin/python

from sys import argv
import os
import math
import urllib.parse
import urllib.request
import random
import os.path
import ssl

def deg2num(lon_deg, lat_deg, zoom):
    lat_rad = math.radians(lat_deg)
    n = 2.0 ** zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi) / 2.0 * n)
    return (xtile, ytile)

def download_url(path_template, cache_bypass_header, zoom, xtile, ytile):
    url = path_template.format(z = zoom, x = xtile, y = ytile)

    headers = {cache_bypass_header: 'true'}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, context=ssl._create_unverified_context()) as response:
        response.read()

def main(argv):
    path_template, cache_bypass_header, bboxD = argv[1], argv[2], list(map(float, argv[3:7]))
    for zoom in range(0, 14 + 1):
        print(zoom)
        minx, miny = deg2num(bboxD[0], bboxD[3], zoom)
        maxx, maxy = deg2num(bboxD[2], bboxD[1], zoom)
        for x in range(max(minx - 2, 0), min(maxx + 2 + 1, 2 ** zoom)):
            for y in range(max(miny - 2, 0), min(maxy + 2 + 1, 2 ** zoom)):
                download_url(path_template, cache_bypass_header, zoom, x, y)

main(argv)
