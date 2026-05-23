"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("//playwright/private:browser_targets.bzl", "compute_browser_targets", "render_workspace_files")
load("//playwright/private:known_browsers.bzl", "KNOWN_BROWSER_INTEGRITY")
load("//playwright/private:util.bzl", "get_browsers_json_path")

_PLAYWRIGHT_PACKAGE = "playwright"
_PLAYWRIGHT_TEST_PACKAGE = "@playwright/test"
_PLAYWRIGHT_PACKAGES = [_PLAYWRIGHT_PACKAGE, _PLAYWRIGHT_TEST_PACKAGE]

def _find_playwright_version_in_deps(deps_dict):
    for package in _PLAYWRIGHT_PACKAGES:
        if package in deps_dict:
            return deps_dict[package]
    return None

def _extract_playwright_version(package_json_data):
    version = _find_playwright_version_in_deps(package_json_data.get("dependencies", {}))
    if not version:
        version = _find_playwright_version_in_deps(package_json_data.get("devDependencies", {}))

    return version

def _playwright_repo_impl(ctx):
    if ctx.attr.playwright_version and ctx.attr.playwright_version_from:
        fail("playwright_version and playwright_version_from cannot both be set")

    if not ctx.attr.playwright_version and not ctx.attr.playwright_version_from and not ctx.attr.browsers_json:
        fail("one of playwright_version or playwright_version_from or browsers_json must be set")

    playwright_version = ctx.attr.playwright_version

    if ctx.attr.playwright_version_from:
        ctx.watch(ctx.attr.playwright_version_from)
        package_json_content = ctx.read(ctx.attr.playwright_version_from)
        package_json_data = json.decode(package_json_content)
        playwright_version = _extract_playwright_version(package_json_data)
        if not playwright_version:
            fail("playwright not found in dependencies or devDependencies")

    if ctx.attr.browsers_json:
        ctx.watch(ctx.attr.browsers_json)
    browsers_json_path = get_browsers_json_path(ctx, playwright_version, ctx.attr.browsers_json)
    browsers_json = ctx.read(browsers_json_path)
    download_paths_json = ctx.read(Label("//playwright/private/cli:src/download_paths.json"))
    browser_targets = compute_browser_targets(ctx.attr.browsers_workspace_name_prefix, browsers_json, download_paths_json)
    files = render_workspace_files(browser_targets, ctx.attr.rules_playwright_cannonical_name)
    ctx.file("BUILD.bazel", files["BUILD.bazel"])
    ctx.file("aliases/BUILD.bazel", files["aliases/BUILD.bazel"])
    ctx.file("browsers/BUILD.bazel", files["browsers/BUILD.bazel"])

    if hasattr(ctx, "repo_metadata"):
        return ctx.repo_metadata(reproducible = True)
    return None

playwright_repository = repository_rule(
    _playwright_repo_impl,
    doc = "Fetch external tools needed for playwright toolchain",
    attrs = {
        "playwright_version": attr.string(
            mandatory = False,
            doc = "The version of playwright to install",
        ),
        "playwright_version_from": attr.label(
            mandatory = False,
            allow_single_file = [".json"],
            doc = "The package.json file to use to find the version of playwright to install",
        ),
        "browsers_json": attr.label(
            allow_single_file = True,
            doc = "The browsers.json file to use. For example https://unpkg.com/playwright-core@1.51.0/browsers.json",
        ),
        "browsers_workspace_name_prefix": attr.string(
            mandatory = True,
            doc = "The namespace prefix used when defining browser workspace repositories.",
        ),
        "rules_playwright_cannonical_name": attr.string(
            mandatory = True,
            doc = "The cannonical name given to the rules_playwright repository. See https://bazel.build/external/module",
        ),
    },
)

def _define_browsers_impl(rctx):
    rctx.watch(rctx.attr.browsers_json)
    download_paths_json = rctx.read(Label("//playwright/private/cli:src/download_paths.json"))
    browser_targets = compute_browser_targets(
        rctx.attr.name,
        rctx.read(rctx.path(rctx.attr.browsers_json)),
        download_paths_json,
    )

    result_build = [
        """load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")""",
        "def fetch_browsers():",
    ]

    # Create a new dictionary by merging the known browser integrity with the user-provided integrity
    # User-provided integrity takes precedence
    integrity_map = dict(KNOWN_BROWSER_INTEGRITY)
    for key, value in rctx.attr.browser_integrity.items():
        integrity_map[key] = value

    for target in browser_targets:
        path = target["http_file_path"]
        integrity_attr = ""
        if path in integrity_map:
            integrity_attr = 'integrity = "{}",\n'.format(integrity_map[path])

        urls_attr = "urls = [\n"
        for url in rctx.attr.browsers_download_urls:
            urls_attr = urls_attr + "\"{}/{}\",\n".format(url, path)
        urls_attr = urls_attr + "],"

        result_build.append("""\
        http_file(
            name = "{name}",
            {integrity} 
            {urls}
        )
""".format(
            name = target["http_file_workspace_name"],
            path = path,
            integrity = integrity_attr,
            urls = urls_attr,
        ))

    rctx.file("browsers.bzl", "\n".join(result_build))
    rctx.file("BUILD", "# no targets")

    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

define_browsers = repository_rule(
    implementation = _define_browsers_impl,
    attrs = {
        "browsers_json": attr.label(allow_single_file = True),
        "browsers_download_urls": attr.string_list(
            default = [
                "https://cdn.playwright.dev/dbazure/download/playwright",
                "https://playwright.download.prss.microsoft.com/dbazure/download/playwright",
                "https://cdn.playwright.dev",
            ],
            doc = "URLs to download playwright browsers from. Replace defaults if a mirror location is preferred.",
        ),
        "browser_integrity": attr.string_dict(
            doc = "A dictionary of browser names to their integrity hashes",
            default = {},
        ),
    },
)
