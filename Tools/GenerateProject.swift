#!/usr/bin/env swift
//
//  GenerateProject.swift
//  Regenerates KocharianAI.xcodeproj/project.pbxproj and the shared scheme
//  from whatever Swift files currently live in KocharianAI/.
//
//  Run from the repository root after adding or deleting a source file:
//
//      swift Tools/GenerateProject.swift
//
//  Object ids are MD5-derived, so the output is byte-stable across runs.
//

import CryptoKit
import Foundation

let app = "KocharianAI"
let productName = "Kocharian AI"
let bundleID = "com.kocharian.ai"
let deploymentTarget = "16.0"

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceRoot = root.appendingPathComponent(app)

guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
    print("error: run this from the repository root (no \(app)/ folder here)")
    exit(1)
}

// MARK: - Helpers

func oid(_ parts: String...) -> String {
    let digest = Insecure.MD5.hash(data: Data(parts.joined(separator: "|").utf8))
    return String(digest.map { String(format: "%02X", $0) }.joined().prefix(24))
}

func swiftSources() -> [String] {
    var found: [String] = []
    let enumerator = FileManager.default.enumerator(at: sourceRoot,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])
    while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension == "xcassets" {
            enumerator?.skipDescendants()
            continue
        }
        guard url.pathExtension == "swift" else { continue }
        let rel = url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
        found.append(rel)
    }
    // top-level files first, then folders, alphabetically
    return found.sorted {
        let lhsDepth = $0.contains("/") ? 1 : 0
        let rhsDepth = $1.contains("/") ? 1 : 0
        return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
    }
}

// MARK: - Collect files

let sources = swiftSources()
let resources = ["Assets.xcassets"]

var buildFiles: [String] = []
var fileRefs: [String] = []
var sourcePhase: [String] = []
var resourcePhase: [String] = []
var groups: [String: [String]] = [:]

for rel in sources + resources + ["Info.plist"] {
    let parts = rel.split(separator: "/").map(String.init)
    let name = parts.last ?? rel
    let folder = parts.count > 1 ? parts.dropLast().joined(separator: "/") : ""
    let fid = oid("file", rel)
    let kind: String
    if name.hasSuffix(".swift") { kind = "sourcecode.swift" }
    else if name.hasSuffix(".xcassets") { kind = "folder.assetcatalog" }
    else { kind = "text.plist.xml" }

    fileRefs.append("\t\t\(fid) /* \(name) */ = {isa = PBXFileReference; lastKnownFileType = \(kind); path = \(name); sourceTree = \"<group>\"; };")
    groups[folder, default: []].append("\t\t\t\t\(fid) /* \(name) */,")

    if sources.contains(rel) || resources.contains(rel) {
        let phase = sources.contains(rel) ? "Sources" : "Resources"
        let bid = oid("build", rel)
        buildFiles.append("\t\t\(bid) /* \(name) in \(phase) */ = {isa = PBXBuildFile; fileRef = \(fid) /* \(name) */; };")
        if phase == "Sources" {
            sourcePhase.append("\t\t\t\t\(bid) /* \(name) in Sources */,")
        } else {
            resourcePhase.append("\t\t\t\t\(bid) /* \(name) in Resources */,")
        }
    }
}

// MARK: - Groups

let subfolders = groups.keys.filter { !$0.isEmpty }.sorted()
var appChildren = subfolders.map { "\t\t\t\t\(oid("group", $0)) /* \($0) */," }
appChildren += (groups[""] ?? []).sorted()

var groupObjects: [String] = []
groupObjects.append("""
\t\t\(oid("group", "app")) /* \(app) */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\(appChildren.joined(separator: "\n"))
\t\t\t);
\t\t\tpath = \(app);
\t\t\tsourceTree = "<group>";
\t\t};
""")
for folder in subfolders {
    groupObjects.append("""
\t\t\(oid("group", folder)) /* \(folder) */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\((groups[folder] ?? []).sorted().joined(separator: "\n"))
\t\t\t);
\t\t\tpath = \(folder);
\t\t\tsourceTree = "<group>";
\t\t};
""")
}

// MARK: - Ids & build settings

func id(_ name: String) -> String { oid("obj", name) }

let common = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = \(deploymentTarget);
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;
"""

let targetCommon = """
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = \(app)/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \(bundleID);
\t\t\t\tPRODUCT_NAME = "\(productName)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

// MARK: - Assemble

let pbx = """
// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

/* Begin PBXBuildFile section */
\(buildFiles.sorted().joined(separator: "\n"))
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t\(id("product")) /* \(productName).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "\(productName).app"; sourceTree = BUILT_PRODUCTS_DIR; };
\(fileRefs.sorted().joined(separator: "\n"))
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t\(id("frameworks")) /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t\(id("main")) = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t\(oid("group", "app")) /* \(app) */,
\t\t\t\t\(id("products")) /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\(groupObjects.joined(separator: "\n"))
\t\t\(id("products")) /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t\(id("product")) /* \(productName).app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t\(id("target")) /* \(app) */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = \(id("cfg_target")) /* Build configuration list for PBXNativeTarget "\(app)" */;
\t\t\tbuildPhases = (
\t\t\t\t\(id("sources")) /* Sources */,
\t\t\t\t\(id("frameworks")) /* Frameworks */,
\t\t\t\t\(id("resources")) /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = \(app);
\t\t\tproductName = \(app);
\t\t\tproductReference = \(id("product")) /* \(productName).app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t\(id("root")) /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t\(id("target")) = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = \(id("cfg_project")) /* Build configuration list for PBXProject "\(app)" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = \(id("main"));
\t\t\tproductRefGroup = \(id("products")) /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t\(id("target")) /* \(app) */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t\(id("resources")) /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\(resourcePhase.sorted().joined(separator: "\n"))
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t\(id("sources")) /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\(sourcePhase.sorted().joined(separator: "\n"))
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t\(id("debug_p")) /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\(common)
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t\(id("release_p")) /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\(common)
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t\(id("debug_t")) /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\(targetCommon)
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t\(id("release_t")) /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\(targetCommon)
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t\(id("cfg_project")) /* Build configuration list for PBXProject "\(app)" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t\(id("debug_p")) /* Debug */,
\t\t\t\t\(id("release_p")) /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t\(id("cfg_target")) /* Build configuration list for PBXNativeTarget "\(app)" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t\(id("debug_t")) /* Debug */,
\t\t\t\t\(id("release_t")) /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */
\t};
\trootObject = \(id("root")) /* Project object */;
}

"""

let scheme = """
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "\(id("target"))"
               BuildableName = "\(productName).app"
               BlueprintName = "\(app)"
               ReferencedContainer = "container:\(app).xcodeproj">
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
            BlueprintIdentifier = "\(id("target"))"
            BuildableName = "\(productName).app"
            BlueprintName = "\(app)"
            ReferencedContainer = "container:\(app).xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "\(id("target"))"
            BuildableName = "\(productName).app"
            BlueprintName = "\(app)"
            ReferencedContainer = "container:\(app).xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>

"""

// MARK: - Write

let projectDir = root.appendingPathComponent("\(app).xcodeproj")
let schemeDir = projectDir.appendingPathComponent("xcshareddata/xcschemes")
try? FileManager.default.createDirectory(at: schemeDir, withIntermediateDirectories: true)
try pbx.write(to: projectDir.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
try scheme.write(to: schemeDir.appendingPathComponent("\(app).xcscheme"), atomically: true, encoding: .utf8)

print("Regenerated \(app).xcodeproj with \(sources.count) Swift files.")
