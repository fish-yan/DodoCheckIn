#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; run after adding/removing Swift files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "DodoCheckIn.xcodeproj"


def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


objects = {}


def add(name, body):
    key = identifier(name)
    objects[key] = body
    return key


def array(values):
    return "(" + ", ".join(values) + ",)" if values else "()"


def settings(values):
    return "{ " + " ".join(f"{key} = {json.dumps(value, ensure_ascii=False)};" for key, value in values.items()) + " }"


def file(path, kind):
    return add("file:" + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {json.dumps(path, ensure_ascii=False)}; sourceTree = SOURCE_ROOT;')


sources = sorted(str(path.relative_to(ROOT)) for folder in ["App", "Sources/DodoCore"] for path in (ROOT / folder).rglob("*.swift"))
test_sources = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "UITests").glob("*.swift"))
resources = ["App/Assets.xcassets", "App/PrivacyInfo.xcprivacy", "Sources/DodoCore/Resources/2026.json", "Sources/DodoCore/Resources/holiday-cn-LICENSE.txt"]
references = []


def phase(name, paths, phase_type, kind):
    builds = []
    for path in paths:
        extension = Path(path).suffix
        file_kind = {".swift": "sourcecode.swift", ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml", ".json": "text.json"}.get(extension, kind)
        reference = file(path, file_kind)
        if reference not in references:
            references.append(reference)
        builds.append(add(f"build:{name}:{path}", f"isa = PBXBuildFile; fileRef = {reference};"))
    return add(name, f"isa = {phase_type}; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")


source_phase = phase("sources", sources, "PBXSourcesBuildPhase", "sourcecode.swift")
resource_phase = phase("resources", resources, "PBXResourcesBuildPhase", "text")
test_phase = phase("test-sources", test_sources, "PBXSourcesBuildPhase", "sourcecode.swift")
framework_phase = phase("frameworks", [], "PBXFrameworksBuildPhase", "wrapper.framework")
test_framework_phase = phase("test-frameworks", [], "PBXFrameworksBuildPhase", "wrapper.framework")

product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = DodoCheckIn.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DodoCheckInUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add("products", f"isa = PBXGroup; children = {array([product, test_product])}; name = Products; sourceTree = \"<group>\";")
main_group = add("main-group", f"isa = PBXGroup; children = {array(references + [products])}; sourceTree = \"<group>\";")

common = {
    "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "SDKROOT": "iphoneos", "CLANG_ENABLE_MODULES": "YES", "TARGETED_DEVICE_FAMILY": "1",
    "CODE_SIGN_STYLE": "Automatic", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
}
app_settings = {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.duoduo.checkin", "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "多多打卡",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.education",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0", "SWIFT_EMIT_LOC_STRINGS": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
}
test_settings = {
    "PRODUCT_BUNDLE_IDENTIFIER": "com.duoduo.checkin.uitests", "PRODUCT_NAME": "$(TARGET_NAME)",
    "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "DodoCheckIn",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
}


def configuration_list(name, extra):
    configs = []
    for configuration in ["Debug", "Release"]:
        values = {**common, **extra}
        values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym"})
        if configuration == "Debug":
            values.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES"})
        configs.append(add(f"config:{name}:{configuration}", f"isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {configuration};"))
    return add("configs:" + name, f"isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


project_configs = configuration_list("project", {})
app_configs = configuration_list("app", app_settings)
test_configs = configuration_list("tests", test_settings)
app_target = add("app-target", f"isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {array([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = (); name = DodoCheckIn; productName = DodoCheckIn; productReference = {product}; productType = \"com.apple.product-type.application\";")
proxy = add("test-proxy", f"isa = PBXContainerItemProxy; containerPortal = {identifier('project')}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = DodoCheckIn;")
dependency = add("test-dependency", f"isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};")
test_target = add("test-target", f"isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {array([test_phase, test_framework_phase])}; buildRules = (); dependencies = {array([dependency])}; name = DodoCheckInUITests; productName = DodoCheckInUITests; productReference = {test_product}; productType = \"com.apple.product-type.bundle.ui-testing\";")
root = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; BuildIndependentTargetsInParallel = YES; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app_target, test_target])};')
PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n archiveVersion = 1; classes = {}; objectVersion = 56;\n objects = {\n" + "\n".join(f"  {key} = {{ {body} }};" for key, body in objects.items()) + f"\n }};\n rootObject = {root};\n}}\n")
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)


def buildable(target, name, product_name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product_name}" BlueprintName="{name}" ReferencedContainer="container:DodoCheckIn.xcodeproj"/>'


app_ref = buildable(app_target, "DodoCheckIn", "DodoCheckIn.app")
test_ref = buildable(test_target, "DodoCheckInUITests", "DodoCheckInUITests.xctest")
(scheme_dir / "DodoCheckIn.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated {PROJECT.name}: {len(sources)} app source files, {len(test_sources)} UI test files")
