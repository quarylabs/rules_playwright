"Make releases for platforms supported by rules_playwright"

def rust_binary(name, visibility = [], **kwargs):
    native.filegroup(
        name = name,
        srcs = kwargs.get("srcs", []),
        visibility = visibility,
    )
