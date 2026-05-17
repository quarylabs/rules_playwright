"""Small rule which unzip a browser to a tree artifact using bash.
"""

load(":unzip_browser.bzl", "UnzippedBrowserInfo")

def _playwright_integrity_map_impl(ctx):
    output = ctx.actions.declare_file(ctx.attr.output if ctx.attr.output else ctx.attr.name + ".json")

    browser_pairs = []
    inputs = []
    for browser in ctx.attr.browsers:
        http_file_path = browser[UnzippedBrowserInfo].http_file_path
        browser_archive = browser[UnzippedBrowserInfo].browser_archive

        inputs.append(browser_archive)
        browser_pairs.append("{}:{}".format(http_file_path, browser_archive.path))

    script = """
set -euo pipefail
out="$1"
silent="$2"
shift 2

tmp="${out}.tmp"
echo "{" > "$tmp"
first=1

for pair in "$@"; do
  key="${pair%%:*}"
  path="${pair#*:}"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$path" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    digest="$(shasum -a 256 "$path" | awk '{print $1}')"
  else
    digest="$(openssl dgst -sha256 "$path" | awk '{print $2}')"
  fi

  if [ "$first" -eq 0 ]; then
    echo "," >> "$tmp"
  fi
  first=0
  printf '  "%s": "sha256-%s"' "$key" "$digest" >> "$tmp"
done

echo >> "$tmp"
echo "}" >> "$tmp"
mv "$tmp" "$out"

if [ "$silent" != "true" ]; then
  printf 'integrity_map = '
  cat "$out"
  echo
fi
"""

    ctx.actions.run_shell(
        inputs = inputs,
        outputs = [output],
        command = script,
        arguments = [output.path, "true" if ctx.attr.silent else "false"] + browser_pairs,
    )

    return [DefaultInfo(files = depset([output]))]

playwright_integrity_map = rule(
    implementation = _playwright_integrity_map_impl,
    attrs = {
        "browsers": attr.label_list(
            providers = [UnzippedBrowserInfo],
            doc = """
                A list of browser targets to generate integrity values for.
                
                These targets should usually be the result of the playwright_browser_matrix() function,
                which creates a cross-product of browser names and platforms.
                Each target must provide the UnzippedBrowserInfo provider.
            """,
        ),
        "output": attr.string(
            doc = """
                The name of the output file to create containing the integrity map.
                
                This file will contain the generated integrity values for the specified browsers.
                Defaults to "target_name.json"
            """,
        ),
        "silent": attr.bool(
            doc = """
                Whether to suppress debug information output.
                
                When set to False (default), the rule will print integrity information
                that users would typically copy and paste into their MODULE.bazel or WORKSPACE file.
                Set to True to prevent this debug output from being printed.
            """,
        ),
    },
)

def playwright_browser_matrix(platforms, browser_names, playwright_repo_name = None, playright_repo_name = None):
    """
    Generates a list of Bazel target labels for browser dependencies.

    This function creates a cross-product of browser names and platforms, constructing
    the appropriate Bazel target labels for each combination.

    "@{playright_repo_name}//browsers:{browser_name}-{platform}"

    Args:
        platforms: A list of platform identifiers (e.g., ['mac14-arm', 'ubuntu20.04-x64]).
        browser_names: A list of browser names (e.g., ['chromium', 'firefox']).
        playwright_repo_name: The name of the Playwright repository.
        playright_repo_name: (DEPRECATED: use playwright_repo_name instead) The name of the Playwright repository.

    Returns:
        A list of browser labels to be used as the browsers attribute of the integrity_map rule.
    """
    # TODO(mrmeku/rules_playwright#26): remove playright_repo_name
    if playwright_repo_name == None and playright_repo_name == None:
        fail("playwright_repo_name must be specified")
    if playwright_repo_name == None:
        print("WARNING: playright_repo_name is deprecated, use playwright_repo_name instead")
        playwright_repo_name = playright_repo_name
    playright_repo_name = None

    browser_labels = []
    for browser in browser_names:
        for platform in platforms:
            browser_labels.append("@{}//browsers:{}-{}".format(playwright_repo_name, browser, platform))
    return browser_labels
