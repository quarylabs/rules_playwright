"""Extensions for bzlmod.

Installs a playwright toolchain.
Every module can define a toolchain version under the default name, "playwright".
The latest of those versions will be selected (the rest discarded),
and will always be registered by rules_playwright.

Additionally, the root module can define arbitrarily many more toolchain versions under different
names (the latest version will be picked for each name) and can register them as it sees fit,
effectively overriding the default named toolchain due to toolchain resolution precedence.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("//playwright/private:browser_targets.bzl", "compute_browser_targets")
load("//playwright/private:known_browsers.bzl", "KNOWN_BROWSER_INTEGRITY")
load("//playwright/private:util.bzl", "get_browsers_json_path")
load(":repositories.bzl", "playwright_repository")

_DEFAULT_NAME = "playwright"

playwright_repo = tag_class(attrs = {
    "name": attr.string(doc = """\
Base name for generated repositories, allowing more than one playwright toolchain to be registered.
Overriding the default is only permitted in the root module.
""", default = _DEFAULT_NAME),
    "playwright_version": attr.string(doc = "Explicit version of playwright to download browsers.json from"),
    "browsers_download_urls": attr.string_list(
        default = [
            # "https://cdn.playwright.dev/dbazure/download/playwright",
            # "https://playwright.download.prss.microsoft.com/dbazure/download/playwright",
            "https://cdn.playwright.dev",
        ],
        doc = "URLs to download playwright browsers from. Replace defaults if a mirror location is preferred.",
    ),
    "browsers_json": attr.label(doc = "Alternative to playwright_version. Skips downloading from unpkg", allow_single_file = True),
    "integrity_map": attr.string_dict(
        default = {},
        doc = "Deprecated: Mapping from brower target to integrity hash",
    ),
    "integrity_path_map": attr.string_dict(
        default = {},
        doc = "Mapping from browser path to integrity hash",
    ),
})

def _extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for repo in mod.tags.repo:
            name = repo.name

            if name != _DEFAULT_NAME and not mod.is_root:
                fail("""\
                Only the root module may override the default name for the playwright toolchain.
                This prevents conflicting registrations in the global namespace of external repos.
                """)

            if not repo.playwright_version and not repo.browsers_json:
                fail("""\
                One of playwright_version or browsers_json must be specified.
                """)

            browsers_json_path = get_browsers_json_path(module_ctx, repo.playwright_version, repo.browsers_json)
            download_paths_json = module_ctx.read(Label("//playwright/private/cli:src/download_paths.json"))
            browser_targets = compute_browser_targets(repo.name, module_ctx.read(browsers_json_path), download_paths_json)

            for browser_target in browser_targets:
                browser_name = browser_target["http_file_workspace_name"]
                path = browser_target["http_file_path"]
                integrity = repo.integrity_map.get(browser_name, None)
                if not integrity:
                    integrity = repo.integrity_path_map.get(path, None)
                    if not integrity:
                        integrity = KNOWN_BROWSER_INTEGRITY.get(path, None)

                urls = [url + "/" + path for url in repo.browsers_download_urls]

                http_file(
                    name = browser_name,
                    integrity = integrity,
                    urls = urls,
                )

            # Step 2: generate repository which references said http_files
            playwright_repository(
                name = name,
                playwright_version = repo.playwright_version,
                browsers_json = repo.browsers_json,
                browsers_workspace_name_prefix = name,
                # Map the apparant name of the module to the cannonical name
                # See https://bazel.build/external/module
                rules_playwright_cannonical_name = "@" + Label("rules_playwright").repo_name,
            )

playwright = module_extension(
    implementation = _extension_impl,
    tag_classes = {"repo": playwright_repo},
)
