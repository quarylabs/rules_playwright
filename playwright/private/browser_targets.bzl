"""Shared browser target computation for repositories and module extensions."""

def _platform_group(platform):
    if platform.endswith("-arm64"):
        if platform.startswith("mac"):
            return "macos_arm64"
        return "linux_arm64"
    if platform.startswith("mac"):
        return "macos_x86_64"
    return "linux_x86_64"

def _base_platform(platform):
    if platform.startswith("ubuntu18.04"):
        return "ubuntu18.04"
    if platform.startswith("ubuntu20.04"):
        return "ubuntu20.04"
    if platform.startswith("ubuntu22.04"):
        return "ubuntu22.04"
    if platform.startswith("ubuntu24.04"):
        return "ubuntu24.04"
    if platform.startswith("debian11"):
        return "debian11"
    if platform.startswith("debian12"):
        return "debian12"
    if platform.startswith("debian13"):
        return "debian13"
    if platform.startswith("mac10.13"):
        return "mac10.13"
    if platform.startswith("mac10.14"):
        return "mac10.14"
    if platform.startswith("mac10.15"):
        return "mac10.15"
    if platform.startswith("mac11"):
        return "mac11"
    if platform.startswith("mac12"):
        return "mac12"
    if platform.startswith("mac13"):
        return "mac13"
    if platform.startswith("mac14"):
        return "mac14"
    if platform.startswith("mac15"):
        return "mac15"
    return None

def _expand_browsers(browsers):
    has_headless = False
    for browser in browsers:
        if browser["name"].endswith("-headless-shell"):
            has_headless = True
            break

    expanded = []
    for browser in browsers:
        expanded.append(browser)
        if has_headless:
            continue
        if browser["name"] in ["chromium", "chromium-tip-of-tree"]:
            copy = dict(browser)
            copy["name"] = "{}-headless-shell".format(browser["name"])
            expanded.append(copy)
    return expanded

def compute_browser_targets(browsers_workspace_name_prefix, browsers_json, download_paths_json):
    """Computes browser target metadata used by repositories and module extension."""
    download_paths = json.decode(download_paths_json)
    decoded = json.decode(browsers_json)
    browsers = _expand_browsers(decoded["browsers"])

    targets = []
    for browser in browsers:
        browser_name = browser["name"]
        if browser_name not in download_paths:
            continue

        revision = browser["revision"]
        revision_overrides = browser.get("revisionOverrides", {})
        browser_version = browser.get("browserVersion", "")

        for platform, template in download_paths[browser_name].items():
            if platform == "<unknown>" or platform.startswith("win") or template == None:
                continue

            current_revision = revision_overrides.get(platform, revision)
            has_revision_override = platform in revision_overrides
            snake_case_browser_name = browser_name.replace("-", "_")
            browser_directory_prefix = snake_case_browser_name
            if has_revision_override:
                browser_directory_prefix = "{}_{}_special".format(snake_case_browser_name, platform)

            path = template.replace("{revision}", current_revision)
            path = path.replace("{browserVersion}", browser_version)

            targets.append({
                "http_file_workspace_name": "{}-{}-{}".format(browsers_workspace_name_prefix, browser_name, platform),
                "http_file_path": path,
                "label": "{}-{}".format(browser_name, platform),
                "output_dir": "{}/{}-{}".format(platform, browser_directory_prefix, revision),
                "browser": browser_name,
                "platform": platform,
            })

    targets = sorted(targets, key = lambda t: t["label"])
    return targets

def render_workspace_files(browser_targets, rules_playwright_cannonical_name):
    """Renders workspace BUILD file contents."""
    browsers_lines = [
        "load(\"@{}//playwright:defs.bzl\", \"unzip_browser\")".format(rules_playwright_cannonical_name),
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]
    for target in browser_targets:
        browsers_lines.extend([
            "unzip_browser(",
            "    name = \"{}\",".format(target["label"]),
            "    browser = \"@{}//file\",".format(target["http_file_workspace_name"]),
            "    output_dir = \"{}\",".format(target["output_dir"]),
            "    http_file_path = \"{}\",".format(target["http_file_path"]),
            ")",
            "",
        ])

    root_targets = {}
    for target in browser_targets:
        browser = target["browser"]
        if browser not in root_targets:
            root_targets[browser] = {}
        group = _platform_group(target["platform"])
        if group not in root_targets[browser]:
            root_targets[browser][group] = {}
        root_targets[browser][group][target["platform"]] = target["label"]

    root_lines = [
        "load(\"@{}//playwright:defs.bzl\", \"select_exec\")".format(rules_playwright_cannonical_name),
        "",
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]
    aliases_lines = [
        "package(default_visibility = [\"//visibility:public\"])",
        "",
    ]

    for browser in sorted(root_targets.keys()):
        groups = root_targets[browser]
        root_lines.extend([
            "select_exec(",
            "    name = \"{}\",".format(browser),
            "    src = select({",
        ])
        for group in sorted(groups.keys()):
            root_lines.append(
                "        \"@{}//tools/platforms:{}\": \"//aliases:{}_{}\",".format(
                    rules_playwright_cannonical_name,
                    group,
                    browser,
                    group,
                ),
            )
        root_lines.extend([
            "    }),",
            ")",
            "",
        ])

        for group in sorted(groups.keys()):
            aliases_lines.extend([
                "alias(",
                "    name = \"{}_{}\",".format(browser, group),
                "    actual = select({",
            ])
            platforms = groups[group]
            for platform in sorted(platforms.keys()):
                base = _base_platform(platform)
                if base == None:
                    continue
                aliases_lines.append(
                    "        \"@{}//tools/platforms:{}\": \"//browsers:{}\",".format(
                        rules_playwright_cannonical_name,
                        base,
                        platforms[platform],
                    ),
                )
            aliases_lines.extend([
                "    }),",
                ")",
                "",
            ])

    return {
        "browsers/BUILD.bazel": "\n".join(browsers_lines).strip() + "\n",
        "BUILD.bazel": "\n".join(root_lines).strip() + "\n",
        "aliases/BUILD.bazel": "\n".join(aliases_lines).strip() + "\n",
    }

