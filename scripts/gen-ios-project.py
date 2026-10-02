#!/usr/bin/env python3
"""Regenerate ios/KocharianAI.xcodeproj/project.pbxproj from the source tree.

Run this after adding or removing a Swift file:

    python3 scripts/gen-ios-project.py

Object ids are md5-derived, so the generated file is stable across runs.
"""
from __future__ import annotations

import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, "ios")
APP = "KocharianAI"
BUNDLE_ID = "com.kocharian.ai"
DEPLOYMENT_TARGET = "16.0"
PRODUCT_NAME = "Kocharian AI"


def oid(*parts: str) -> str:
    return hashlib.md5("|".join(parts).encode()).hexdigest()[:24].upper()


def swift_sources() -> list[str]:
    """Paths relative to ios/KocharianAI, sorted, grouped by folder."""
    base = os.path.join(IOS, APP)
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.endswith(".xcassets")]
        for name in filenames:
            if name.endswith(".swift"):
                rel = os.path.relpath(os.path.join(dirpath, name), base)
                found.append(rel.replace(os.sep, "/"))
    return sorted(found, key=lambda p: (p.count("/") == 0 and "0" or "1", p))


def main() -> None:
    sources = swift_sources()
    resources = ["Assets.xcassets"]

    # ---- sections -------------------------------------------------------
    build_files, file_refs = [], []
    source_phase, resource_phase = [], []
    groups: dict[str, list[str]] = {}

    for rel in sources + resources + ["Info.plist"]:
        folder, _, name = rel.rpartition("/")
        fid = oid("file", rel)
        kind = ("sourcecode.swift" if name.endswith(".swift")
                else "folder.assetcatalog" if name.endswith(".xcassets")
                else "text.plist.xml")
        file_refs.append(
            f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; '
            f'path = {name}; sourceTree = "<group>"; }};')
        groups.setdefault(folder, []).append(f"\t\t\t\t{fid} /* {name} */,")

        if rel in sources or rel in resources:
            bid = oid("build", rel)
            phase = "Sources" if rel in sources else "Resources"
            build_files.append(
                f'\t\t{bid} /* {name} in {phase} */ = {{isa = PBXBuildFile; '
                f'fileRef = {fid} /* {name} */; }};')
            (source_phase if phase == "Sources" else resource_phase).append(
                f"\t\t\t\t{bid} /* {name} in {phase} */,")

    # group objects (root -> KocharianAI -> subfolders)
    group_objects = []
    subfolders = sorted(f for f in groups if f)
    app_children = [f'\t\t\t\t{oid("group", f)} /* {f} */,' for f in subfolders]
    app_children += groups.get("", [])

    group_objects.append(
        f'\t\t{oid("group", "app")} /* {APP} */ = {{\n'
        f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "\n".join(app_children) +
        f"\n\t\t\t);\n\t\t\tpath = {APP};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")

    for folder in subfolders:
        group_objects.append(
            f'\t\t{oid("group", folder)} /* {folder} */ = {{\n'
            f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "\n".join(sorted(groups[folder])) +
            f"\n\t\t\t);\n\t\t\tpath = {folder};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")

    ids = {name: oid("obj", name) for name in
           ["root", "product", "products", "target", "sources", "resources", "frameworks",
            "cfg_project", "cfg_target", "debug_p", "release_p", "debug_t", "release_t", "main"]}

    common = f"""				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				IPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;"""

    target_common = f"""				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = {APP}/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
				PRODUCT_NAME = "{PRODUCT_NAME}";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";"""

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(sorted(build_files))}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{ids['product']} /* {PRODUCT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{PRODUCT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
{chr(10).join(sorted(file_refs))}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['main']} = {{
			isa = PBXGroup;
			children = (
				{oid('group', 'app')} /* {APP} */,
				{ids['products']} /* Products */,
			);
			sourceTree = "<group>";
		}};
{chr(10).join(group_objects)}
		{ids['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['product']} /* {PRODUCT_NAME}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['target']} /* {APP} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['cfg_target']} /* Build configuration list for PBXNativeTarget "{APP}" */;
			buildPhases = (
				{ids['sources']} /* Sources */,
				{ids['frameworks']} /* Frameworks */,
				{ids['resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = {APP};
			productName = {APP};
			productReference = {ids['product']} /* {PRODUCT_NAME}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['root']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{ids['target']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {ids['cfg_project']} /* Build configuration list for PBXProject "{APP}" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ids['main']};
			productRefGroup = {ids['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['target']} /* {APP} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(sorted(resource_phase))}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(sorted(source_phase))}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{ids['debug_p']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{common}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{ids['release_p']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{common}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{ids['debug_t']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{target_common}
			}};
			name = Debug;
		}};
		{ids['release_t']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{target_common}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['cfg_project']} /* Build configuration list for PBXProject "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['debug_p']} /* Debug */,
				{ids['release_p']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['cfg_target']} /* Build configuration list for PBXNativeTarget "{APP}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['debug_t']} /* Debug */,
				{ids['release_t']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {ids['root']} /* Project object */;
}}
"""

    out = os.path.join(IOS, f"{APP}.xcodeproj", "project.pbxproj")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(pbx)
    print(f"wrote {os.path.relpath(out, ROOT)} with {len(sources)} Swift files")

    scheme_dir = os.path.join(IOS, f"{APP}.xcodeproj", "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    scheme = SCHEME.replace("@TARGET@", ids["target"]).replace("@APP@", APP) \
                   .replace("@PRODUCT@", PRODUCT_NAME)
    with open(os.path.join(scheme_dir, f"{APP}.xcscheme"), "w", encoding="utf-8") as fh:
        fh.write(scheme)
    print("wrote shared scheme")


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "@TARGET@"
               BuildableName = "@PRODUCT@.app"
               BlueprintName = "@APP@"
               ReferencedContainer = "container:@APP@.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "@TARGET@"
            BuildableName = "@PRODUCT@.app"
            BlueprintName = "@APP@"
            ReferencedContainer = "container:@APP@.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "@TARGET@"
            BuildableName = "@PRODUCT@.app"
            BlueprintName = "@APP@"
            ReferencedContainer = "container:@APP@.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    main()
