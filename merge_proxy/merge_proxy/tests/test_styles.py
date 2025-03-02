from ..style import StyleGL, StyleGLStylePatch

BASIC = "https://vecto-dev.teritorio.xyz/styles/teritorio-basic-dev/style.json"
TOURISM = "https://vecto-dev.teritorio.xyz/styles/teritorio-tourism-dev/style.json"
BICYCLE = "https://vecto-dev.teritorio.xyz/styles/teritorio-bicycle-dev/style.json"


def test_styleGl():
    StyleGL(
        url=BASIC,
    )


def test_StyleGLStylePatch():
    style_basic = StyleGL(url=BASIC)
    style_tourism = StyleGL(url=TOURISM)

    diff = style_basic.layers_diff(style_basic)
    assert not diff

    diff = style_basic.layers_diff(style_tourism)
    assert diff

    style_basic_patched = style_basic.apply_patch(diff)
    #  Diff on layer list
    assert [layer["id"] for layer in style_tourism.layers()] == [
        layer["id"] for layer in style_basic_patched.layers()
    ]
    #  Full diff
    assert style_tourism.layers() == style_basic_patched.layers()


def test_patch():
    style_basic = StyleGL(url=BASIC)
    style_tourism = StyleGL(url=TOURISM)
    style_bicyle = StyleGL(url=BICYCLE)

    diff_bicycle = style_basic.layers_diff(style_bicyle)
    style_tourism.apply_patch(diff_bicycle)
