from ..sources import SourceTileJSON


def test_tilejson():
    SourceTileJSON(
        tilejson_url="https://vecto-dev.teritorio.xyz/data/teritorio-dev.json",
    )


def test_tilejson_tile_url():
    source = SourceTileJSON(
        tilejson_url="https://vecto-dev.teritorio.xyz/data/teritorio-dev.json",
        tile_url="http://localhost:3000",
    )

    assert source.template_url.startswith("http://localhost:3000")
