"""Small rule which unzip a browser to a tree artifact using bash.
"""

UnzippedBrowserInfo = provider(
    doc = "Provides the sources of an npm package along with the package name and version",
    fields = {
        "http_file_path": "name of the http_file rule used to download the browser",
        "browser_archive": "file from the http_file used to download the browser",
        "output_path": "where the browser was unzipped to",
    },
)

def _unzip_browser_impl(ctx):
    output_dir = ctx.actions.declare_directory(ctx.attr.output_dir)
    ctx.actions.run_shell(
        inputs = [ctx.file.browser],
        outputs = [output_dir],
        command = """
set -euo pipefail
mkdir -p "$1"
unzip -q "$2" -d "$1"
""",
        arguments = [output_dir.path, ctx.file.browser.path],
    )
    return [
        DefaultInfo(files = depset([output_dir])),
        UnzippedBrowserInfo(
            http_file_path = ctx.attr.http_file_path,
            browser_archive = ctx.file.browser,
            output_path = output_dir.path,
        ),
    ]

unzip_browser = rule(
    implementation = _unzip_browser_impl,
    attrs = {
        "http_file_path": attr.string(mandatory = True),
        "browser": attr.label(
            allow_single_file = True,
            mandatory = True,
        ),
        "output_dir": attr.string(mandatory = True),
    },
)
