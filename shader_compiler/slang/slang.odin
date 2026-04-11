// Inspired by https://github.com/DragosPopse/odin-slang by Dragos
// See https://github.com/shader-slang/slang/blob/master/include/slang.h for the original header.
package slang

API_VERSION :: 0

CapabilityID :: distinct i32
ProfileID :: distinct i32

Result :: enum u32 {
    // Windows COM HRESULT Compatible

    OK                      = 0,
    FAIL                    = _ERROR | FACILITY_WIN_GENERAL<<16 | 0x4005,
    E_NOT_IMPLEMENTED       = _ERROR | FACILITY_WIN_GENERAL<<16 | 0x4001,
    E_NO_INTERFACE          = _ERROR | FACILITY_WIN_GENERAL<<16 | 0x4002,
    E_ABORT                 = _ERROR | FACILITY_WIN_GENERAL<<16 | 0x4004,
    E_INVALID_HANDLE        = _ERROR | FACILITY_WIN_API<<16 | 6,
    E_INVALID_ARG           = _ERROR | FACILITY_WIN_API<<16 | 0x57,
    E_OUT_OF_MEMORY         = _ERROR | FACILITY_WIN_API<<16 | 0xe,

    // Other Results

    E_BUFFER_TOO_SMALL      = _ERROR | FACILITY_CORE<<16 | 1, // Supplied buffer is too small to be able to complete
    E_UNINITIALIZED         = _ERROR | FACILITY_CORE<<16 | 2, // Used to identify a Result that has yet to be initialized.
    E_PENDING               = _ERROR | FACILITY_CORE<<16 | 3, // Returned from an async method meaning the output is invalid (thus an error), but a result for the request is pending, and will be returned on a subsequent call with the async handle.
    E_CANNOT_OPEN           = _ERROR | FACILITY_CORE<<16 | 4, // Indicates a file/resource could not be opened
    E_NOT_FOUND             = _ERROR | FACILITY_CORE<<16 | 5, // Indicates a file/resource could not be found
    E_INTERNAL_FAIL         = _ERROR | FACILITY_CORE<<16 | 6, // An unhandled internal failure (typically from unhandled exception)
    E_NOT_AVAILABLE         = _ERROR | FACILITY_CORE<<16 | 7, // Could not complete because some underlying feature (hardware or software) was not available
    E_TIME_OUT              = _ERROR | FACILITY_CORE<<16 | 8, // Could not complete because the operation times out.
}

// SLANG_MAKE_ERROR(fac, code) ((((int32_t)(fac)) << 16) | ((int32_t)(code)) | int32_t(0x80000000))
_ERROR :: 0x80000000
FACILITY_WIN_GENERAL :: 0
FACILITY_WIN_API :: 7
FACILITY_CORE :: 0x200

LanguageVersion :: enum u32 {
    UNKNOWN = 0,
    LEGACY = 2018,
    _2025 = 2025,
    _2026 = 2026,
    LATEST = _2026,
};

#assert(size_of(GlobalSessionDesc) == 80)
GlobalSessionDesc :: struct {
    structureSize: u32, // size_of(GlobalSessionDesc)
    apiVersion: u32,
    minLanguageVersion: LanguageVersion, // Oldest Slang language version that any sessions will use
    enableGLSL: bool,
    reserved: [16]u32, // Reserved for future use
}

GlobalSessionDesc_DEFAULT :: GlobalSessionDesc {
    structureSize      = size_of(GlobalSessionDesc),
    apiVersion         = API_VERSION,
    minLanguageVersion = ._2025,
}

// MARK: Global API

// You must load this yourself.
Global_VTable :: struct {
    // Create a blob from binary data.
    // @param data Pointer to the binary data to store in the blob. Must not be null.
    // @param size Size of the data in bytes. Must be greater than 0.
    // @return The created blob on success, or nil on failure.
    createBlob: proc "c" (data: rawptr, #any_int size: uint) -> ^IBlob,

    // Load a module from source code with size specification.
    // @param session The session to load the module into.
    // @param moduleName The name of the module.
    // @param path The path for the module.
    // @param source Pointer to the source code data.
    // @param sourceSize Size of the source code data in bytes.
    // @param outDiagnostics (out, optional) Diagnostics output.
    // @return The loaded module on success, or nil on failure.
    loadModuleFromSource: proc "c" (
        session: ^ISession,
        moduleName: cstring,
        path: cstring,
        source: cstring,
        sourceSize: uint,
        outDiagnostics: ^^IBlob = nil
    ) -> ^IModule,

    // Load a module from IR data.
    // @param session The session to load the module into.
    // @param moduleName Name of the module to load.
    // @param path Path for the module (used for diagnostics).
    // @param source IR data containing the module.
    // @param sourceSize Size of the IR data in bytes.
    // @param outDiagnostics (out, optional) Diagnostics output.
    // @return The loaded module on success, or nil on failure.
    loadModuleFromIRBlob: proc "c" (
        session: ^ISession,
        moduleName: cstring,
        path: cstring,
        source: rawptr,
        sourceSize: uint,
        outDiagnostics: ^^IBlob = nil,
    ) -> ^IModule,

    // Read module info (name and version) from IR data.
    // @param session The session to use for loading module info.
    // @param source IR data containing the module.
    // @param sourceSize Size of the IR data in bytes.
    // @param outModuleVersion (out) Module version number.
    // @param outModuleCompilerVersion (out) Compiler version that created the module.
    // @param outModuleName (out) Name of the module.
    // @return OK on success, or an error code on failure.
    loadModuleInfoFromIRBlob: proc "c" (
        session: ^ISession,
        source: rawptr,
        sourceSize: uint,
        outModuleVersion: ^int,
        outModuleCompilerVersion: ^cstring,
        outModuleName: ^cstring,
    ) -> Result,

    // Create a global session, with the built-in core module.
    // @param apiVersion Pass VERSION
    // @param outGlobalSession (out)The created global session.
    createGlobalSession: proc "c" (apiVersion: int, outGlobalSession: ^^IGlobalSession) -> Result,

    // Create a global session, with the built-in core module.
    // @param desc Description of the global session.
    // @param outGlobalSession (out)The created global session.
    createGlobalSession2: proc "c" (#by_ptr desc: GlobalSessionDesc, outGlobalSession: ^^IGlobalSession) -> Result,

    // Create a global session, but do not set up the core module. The core module can
    // then be loaded via loadCoreModule or compileCoreModule
    // NOTE! API is experimental and not ready for production code
    // @param apiVersion Pass VERSION
    // @param outGlobalSession (out)The created global session that doesn't have a core module setup.
    createGlobalSessionWithoutCoreModule: proc "c" (apiVersion: int, outGlobalSession: ^^IGlobalSession) -> Result,

    // Returns a blob that contains the serialized core module.
    // Returns nil if there isn't an embedded core module.
    // NOTE! API is experimental and not ready for production code
    // getEmbeddedCoreModule: proc "c" () -> ^IBlob,

    // Cleanup all global allocations used by Slang, to prevent memory leak detectors from
    // reporting them as leaks. This function should only be called after all Slang objects
    // have been released. No other Slang functions such as `createGlobalSession`
    // should be called after this function.
    shutdown: proc "c" (),

    // Return the last signaled internal error message.
    // getLastinternalErrorMessage: proc "c" () -> cstring,
}

// MARK: Types

ShaderReflection :: struct {}
TypeReflection :: struct {}
TypeLayoutReflection :: struct {}
FunctionReflection :: struct {}
DeclReflection :: struct {}

ProgramLayout :: struct {}
SpecializationArg :: struct {}
ICompileRequest :: struct {}

PassThrough :: enum i32 {
    None,
    FXC,
    DXC,
    GLSLANG,
    SPIRV_DIS,
    CLANG,
    VISUAL_STUDIO,
    GCC,
    GENERIC_C_CPP,
    NVRTC,
    LLVM,
    SPIRV_OPT,
    METAL,
    Tint,
    SPIRV_LINK,
}

BuiltinModuleName :: enum i32 {
    Core,
    GLSL,
}

CompileCoreModuleFlag :: enum u32 {
    WriteDocumentation = 0x1,
}

MatrixLayoutMode :: enum u32 {
    UNKNOWN,
    ROW_MAJOR,
    COLUMN_MAJOR,
}

SourceLanguage :: enum i32 {
    Unknown,
    SLANG,
    HLSL,
    GLSL,
    C,
    CPP,
    CUDA,
    SPIRV,
    METAL,
    WGSL,
}

CompileTarget :: enum i32 {
    UNKNOWN,
    None,
    GLSL,
    GLSL_VULKAN_DEPRECATED,
    GLSL_VULKAN_ONE_DESC_DEPRECATED,
    HLSL,
    SPIRV,
    SPIRV_ASM,
    DXBC,
    DXBC_ASM,
    DXIL,
    DXIL_ASM,
    C_SOURCE,
    CPP_SOURCE,
    HOST_EXECUTABLE,
    SHADER_SHARED_LIBRARY,
    SHADER_HOST_CALLABLE,
    CUDA_SOURCE,
    PTX,
    CUDA_OBJECT_CODE,
    OBJECT_CODE,
    HOST_CPP_SOURCE,
    HOST_HOST_CALLABLE,
    CPP_PYTORCH_BINDINGS,
    METAL,
    METAL_LIB,
    METAL_LIB_ASM,
    HOST_SHARED_LIBRARY,
    WGSL,
    WGSL_SPIRV_ASM,
    WGSL_SPIRV,
    HOST_VM,
}

Stage :: enum u32 {
    NONE,
    VERTEX,
    HULL,
    DOMAIN,
    GEOMETRY,
    FRAGMENT,
    COMPUTE,
    RAY_GENERATION,
    INTERSECTION,
    ANY_HIT,
    CLOSEST_HIT,
    MISS,
    CALLABLE,
    MESH,
    AMPLIFICATION,
    DISPATCH,
    PIXEL = FRAGMENT, // alias
}

DebugInfoLevel :: enum u32 {
    NONE,
    MINIMAL,
    STANDARD,
    MAXIMAL,
}

DebugInfoFormat :: enum u32 {
    DEFAULT,
    C7,
    PDB,
    STABS,
    COFF,
    DWARF,
}

OptimizationLevel :: enum u32 {
    NONE,
    DEFAULT,
    HIGH,
    MAXIMAL,
}

// Note(Dragos): the enum integral is not specified here
EmitSpirvMethod :: enum i32 {
    DEFAULT,
    VIA_GLSL,
    DIRECTLY,
}

FloatingPointMode :: enum u32 {
    DEFAULT,
    FAST,
    PRECISE,
}

LineDirectiveMode :: enum u32 {
    DEFAULT,
    NONE,
    STANDARD,
    GLSL,
    SOURCE_MAP,
}

TargetDesc :: struct {
    structureSize              : uint, // size_of(TargetDesc)
    format                     : CompileTarget,
    profile                    : ProfileID,
    flags                      : TargetFlags,
    floatingPointMode          : FloatingPointMode,
    lineDirectiveMode          : LineDirectiveMode,
    forceGLSLScalarBufferLayout: bool,
    compilerOptionEntries      : [^]CompilerOptionEntry,
    compilerOptionEntryCount   : u32,
}

TargetFlags :: bit_set[TargetFlag; u32]
TargetFlag :: enum i32 {
    PARAMETER_BLOCK_USE_REGISTER_SPACE = 4, // Deprecated, This behavior is now enabled unconditionally
    GENERATE_WHOLE_PROGRAM = 8,
    DUMP_IR = 9,
    GENERATE_SPIRV_DIRECTLY = 10,
}

#assert(size_of(SessionDesc) == 96)
SessionDesc :: struct {
    structureSize: uint, // size_of(SessionDesc)
    targets: [^]TargetDesc,
    targetCount: int,
    flags: u32,
    defaultMatrixLayoutMode: MatrixLayoutMode,
    searchPaths: [^]cstring,
    searchPathCount: int,
    preprocessorMacros: [^]PreprocessorMacroDesc,
    preprocessorMacroCount: int,
    fileSystem: ^IFileSystem,
    enableEffectAnnotations: bool,
    allowGLSLSyntax: bool,
    compilerOptionEntries: [^]CompilerOptionEntry,
    compilerOptionEntryCount: u32,
    skipSPIRVValidation: bool,
}

PreprocessorMacroDesc :: struct {
    name : cstring,
    value: cstring,
}

ArchiveType :: enum i32 {
    UNDEFINED,
    ZIP,
    RIFF,
    RIFF_DEFLATE,
    RIFF_LZ4,
}

CompilerOptionEntry :: struct {
    name: CompilerOptionName,
    value: CompilerOptionValue,
}

CompilerOptionValue :: struct {
    kind: CompilerOptionValueKind,
    intValue0: i32,
    intValue1: i32,
    stringValue0: cstring,
    stringValue1: cstring,
}

CompilerOptionValueKind :: enum i32 {
    Int,
    String,
}

CompilerOptionName :: enum i32 {
    MacroDefine, // stringValue0: macro name;  stringValue1: macro value
    DepFile,
    EntryPointName,
    Specialize,
    Help,
    HelpStyle,
    Include, // stringValue: additional include path.
    Language,
    MatrixLayoutColumn,         // bool
    MatrixLayoutRow,            // bool
    ZeroInitialize,             // bool
    IgnoreCapabilities,         // bool
    RestrictiveCapabilityCheck, // bool
    ModuleName,                 // stringValue0: module name.
    Output,
    Profile, // intValue0: profile
    Stage,   // intValue0: stage
    Target,  // intValue0: CodeGenTarget
    Version,
    WarningsAsErrors, // stringValue0: "all" or comma separated list of warning codes or names.
    DisableWarnings,  // stringValue0: comma separated list of warning codes or names.
    EnableWarning,    // stringValue0: warning code or name.
    DisableWarning,   // stringValue0: warning code or name.
    DumpWarningDiagnostics,
    InputFilesRemain,
    EmitIr,                        // bool
    ReportDownstreamTime,          // bool
    ReportPerfBenchmark,           // bool
    ReportCheckpointIntermediates, // bool
    SkipSPIRVValidation,           // bool
    SourceEmbedStyle,
    SourceEmbedName,
    SourceEmbedLanguage,
    DisableShortCircuit,            // bool
    MinimumSlangOptimization,       // bool
    DisableNonEssentialValidations, // bool
    DisableSourceMap,               // bool
    UnscopedEnum,                   // bool
    PreserveParameters, // bool: preserve all resource parameters in the output code.
    // Target

    Capability,                // intValue0: CapabilityName
    DefaultImageFormatUnknown, // bool
    DisableDynamicDispatch,    // bool
    DisableSpecialization,     // bool
    FloatingPointMode,         // intValue0: FloatingPointMode
    DebugInformation,          // intValue0: DebugInfoLevel
    LineDirectiveMode,
    Optimization, // intValue0: OptimizationLevel
    Obfuscate,    // bool

    VulkanBindShift, // intValue0 (higher 8 bits): kind; intValue0(lower bits): set; intValue1:
                    // shift. Kind is HLSLToVulkanLayoutBindingKind
    VulkanBindGlobals,       // intValue0: index; intValue1: set
    VulkanInvertY,           // bool
    VulkanUseDxPositionW,    // bool
    VulkanUseEntryPointName, // bool
    VulkanUseGLLayout,       // bool
    VulkanEmitReflection,    // bool

    GLSLForceScalarLayout,   // bool
    EnableEffectAnnotations, // bool

    EmitSpirvViaGLSL,     // bool (will be deprecated)
    EmitSpirvDirectly,    // bool (will be deprecated)
    SPIRVCoreGrammarJSON, // stringValue0: json path
    IncompleteLibrary,    // bool, when set, will not issue an error when the linked program has
                        // unresolved extern function symbols.

    // Downstream

    CompilerPath,
    DefaultDownstreamCompiler,
    DownstreamArgs, // stringValue0: downstream compiler name. stringValue1: argument list, one
                    // per line.
    PassThrough,

    // Repro

    DumpRepro,
    DumpReproOnError,
    ExtractRepro,
    LoadRepro,
    LoadReproDirectory,
    ReproFallbackDirectory,

    // Debugging

    DumpAst,
    DumpIntermediatePrefix,
    DumpIntermediates, // bool
    DumpIr,            // bool
    DumpIrIds,
    PreprocessorOutput,
    OutputIncludes,
    ReproFileSystem,
    REMOVED_SerialIR, // deprecated and removed
    SkipCodeGen,      // bool
    ValidateIr,       // bool
    VerbosePaths,
    VerifyDebugSerialIr,
    NoCodeGen, // Not used.

    // Experimental

    FileSystem,
    Heterogeneous,
    NoMangle,
    NoHLSLBinding,
    NoHLSLPackConstantBufferElements,
    ValidateUniformity,
    AllowGLSL,
    EnableExperimentalPasses,
    BindlessSpaceIndex, // int
    SPIRVResourceHeapStride,
    SPIRVSamplerHeapStride,

    // Internal

    ArchiveType,
    CompileCoreModule,
    Doc,

    IrCompression, //< deprecated

    LoadCoreModule,
    ReferenceModule,
    SaveCoreModule,
    SaveCoreModuleBinSource,
    TrackLiveness,
    LoopInversion, // bool, enable loop inversion optimization

    ParameterBlocksUseRegisterSpaces, // Deprecated
    LanguageVersion,                  // intValue0: SlangLanguageVersion
    TypeConformance, // stringValue0: additional type conformance to link, in the format of
                    // "<TypeName>:<IInterfaceName>[=<sequentialId>]", for example
                    // "Impl:IFoo=3" or "Impl:IFoo".
    EnableExperimentalDynamicDispatch, // bool, experimental
    EmitReflectionJSON,                // bool

    CountOfParsableOptions,

    // Used in parsed options only.
    DebugInformationFormat,  // intValue0: DebugInfoFormat
    VulkanBindShiftAll,      // intValue0: kind; intValue1: shift
    GenerateWholeProgram,    // bool
    UseUpToDateBinaryModule, // bool, when set, will only load
                            // precompiled modules if it is up-to-date with its source.
    EmbedDownstreamIR,       // bool
    ForceDXLayout,           // bool

    // Add this new option to the end of the list to avoid breaking ABI as much as possible.
    // Setting of EmitSpirvDirectly or EmitSpirvViaGLSL will turn into this option internally.
    EmitSpirvMethod, // enum SlangEmitSpirvMethod

    SaveGLSLModuleBinSource,

    SkipDownstreamLinking, // bool, experimental
    DumpModule,

    GetModuleInfo,              // Print serialized module version and name
    GetSupportedModuleVersions, // Print the min and max module versions this compiler supports

    EmitSeparateDebug, // bool

    // Floating point denormal handling modes
    DenormalModeFp16,
    DenormalModeFp32,
    DenormalModeFp64,

    // Bitfield options
    UseMSVCStyleBitfieldPacking, // bool

    ForceCLayout, // bool

    ExperimentalFeature, // bool, enable experimental features

    ReportDetailedPerfBenchmark, // bool, reports detailed compiler performance benchmark
                                // results
    ValidateIRDetailed,          // bool, enable detailed IR validation
    DumpIRBefore,                // string, pass name to dump IR before
    DumpIRAfter,                 // string, pass name to dump IR after

    EmitCPUMethod,    // enum SlangEmitCPUMethod
    EmitCPUViaCPP,    // bool
    EmitCPUViaLLVM,   // bool
    LLVMTargetTriple, // string
    LLVMCPU,          // string
    LLVMFeatures,     // string

    EnableRichDiagnostics, // bool, enable the experimental rich diagnostics

    ReportDynamicDispatchSites, // bool

    EnableMachineReadableDiagnostics, // bool, enable machine-readable diagnostic output
                                    // (implies EnableRichDiagnostics)

    DiagnosticColor, // intValue0: SlangDiagnosticColor (always, never, auto)
}

ParameterCategory :: enum u32 {
    NONE,
    MIXED,
    CONSTANT_BUFFER,
    SHADER_RESOURCE,
    UNORDERED_ACCESS,
    VARYING_INPUT,
    VARYING_OUTPUT,
    SAMPLER_STATE,
    UNIFORM,
    DESCRIPTOR_TABLE_SLOT,
    SPECIALIZATION_CONSTANT,
    PUSH_CONSTANT_BUFFER,

    // HLSL register `space`, Vulkan GLSL `set`
    REGISTER_SPACE,

    // TODO: Ellie, Both APIs treat mesh outputs as more or less varying output,
    // Does it deserve to be represented here??

    // A parameter whose type is to be specialized by a global generic type argument
    GENERIC,

    RAY_PAYLOAD,
    HIT_ATTRIBUTES,
    CALLABLE_PAYLOAD,
    SHADER_RECORD,

    // An existential type parameter represents a "hole" that
    // needs to be filled with a concrete type to enable
    // generation of specialized code.
    //
    // Consider this example:
    //
    //      struct MyParams
    //      {
    //          IMaterial material;
    //          ILight lights[3];
    //      };
    //
    // This `MyParams` type introduces two existential type parameters:
    // one for `material` and one for `lights`. Even though `lights`
    // is an array, it only introduces one type parameter, because
    // we need to have a *single* concrete type for all the array
    // elements to be able to generate specialized code.
    //
    EXISTENTIAL_TYPE_PARAM,

    // An existential object parameter represents a value
    // that needs to be passed in to provide data for some
    // interface-type shader parameter.
    //
    // Consider this example:
    //
    //      struct MyParams
    //      {
    //          IMaterial material;
    //          ILight lights[3];
    //      };
    //
    // This `MyParams` type introduces four existential object parameters:
    // one for `material` and three for `lights` (one for each array
    // element). This is consistent with the number of interface-type
    // "objects" that are being passed through to the shader.
    //
    EXISTENTIAL_OBJECT_PARAM,

    // The register space offset for the sub-elements that occupies register spaces.
    SUB_ELEMENT_REGISTER_SPACE,

    // The input_attachment_index subpass occupancy tracker
    SUBPASS,

    // Metal tier-1 argument buffer element [[id]].
    METAL_ARGUMENT_BUFFER_ELEMENT,

    // Metal [[attribute]] inputs.
    METAL_ATTRIBUTE,

    // Metal [[payload]] inputs
    METAL_PAYLOAD,

    //
    COUNT,

    // Aliases for Metal-specific categories.
    METAL_BUFFER = CONSTANT_BUFFER,
    METAL_TEXTURE = SHADER_RESOURCE,
    METAL_SAMPLER = SAMPLER_STATE,

    // DEPRECATED:
    VERTEX_INPUT = VARYING_INPUT,
    FRAGMENT_OUTPUT = VARYING_OUTPUT,
    COUNT_V1 = SUBPASS,
}

// https://github.com/shader-slang/slang/blob/e40b35c3984d0f2b0b890972f927fc3264d3a955/source/slang/slang-hlsl-to-vulkan-layout-options.h#L43
HLSLToVulkanLayoutBindingKind :: enum i32 {
    Invalid = -1,

    /// Unordered access view (u)
    ///
    /// RWByteAddressBuffer/RWStructuredBuffer
    /// Append/ConsumeStructuredBuffer
    /// RWBuffer
    /// RWTextureXD/Array
    UnorderedAccess = 0,

    /// Sampler (s)
    ///
    /// SamplerXD
    /// SamplerState/SamplerComparisonState
    Sampler,

    /// Shader Resource (t)
    ///
    /// TextureXD/Array
    /// ByteAddressBuffer/StructuredBuffer/Buffer/TBuffer
    ShaderResource,

    /// Constant buffer (b)
    ///
    /// ConstantBufferViews, CBuffer
    ConstantBuffer,
};

LayoutRules :: enum u32 {
    DEFAULT,
    METAL_ARGUMENT_BUFFER_TIER_2,
}

ContainerType :: enum i32 {
    None,
    UnsizedArray,
    StructuredBuffer,
    ConstantBuffer,
    ParameterBlock,
}

// MARK: COM API

UUID :: struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
}

IBlob_UUID :: UUID{0x8BA5FB08, 0x5195,0x40e2, {0xAC, 0x58, 0x0D, 0x98, 0x9C, 0x3A, 0x01, 0x02}}
IUnknown_UUID :: UUID{0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
ICastable_UUID :: UUID{0x87ede0e1, 0x4852, 0x44b0, {0x8b, 0xf2, 0xcb, 0x31, 0x87, 0x4d, 0xe2, 0x39}}
IFileSystem_UUID :: UUID{0x003A09FC, 0x3A4D, 0x4BA0, {0xAD, 0x60, 0x1F, 0xD8, 0x63, 0xA9, 0x15, 0xAB}}

ISession :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^struct {
        using iunknown_vtable: IUnknown_VTable,
        getGlobalSession                        : proc "system" (this: ^ISession) -> ^IGlobalSession,
        loadModule                              : proc "system" (this: ^ISession, moduleName: cstring, outDiagnostics: ^^IBlob) -> ^IModule,
        loadModuleFromSource                    : proc "system" (this: ^ISession, moduleName: cstring, path: cstring, source: ^IBlob, outDiagnostics: ^^IBlob) -> ^IModule,
        createCompositeComponentType            : proc "system" (this: ^ISession, componentTypes: [^]^IComponentType, #any_int componentTypeCount: int, outCompositeComponentType: ^^IComponentType, outDiagnostics: ^^IBlob) -> Result,
        specializeType                          : proc "system" (this: ^ISession, type: ^TypeReflection, specializationArgs: [^]SpecializationArg, specializationArgCount: int, outDiagnostics: ^^IBlob) -> ^TypeReflection,
        getTypeLayout                           : proc "system" (this: ^ISession, type: ^TypeReflection, targetIndex: int, rules: LayoutRules, outDiagnostics: ^^IBlob) -> ^TypeLayoutReflection,
        getContainerType                        : proc "system" (this: ^ISession, elementType: ^TypeReflection, containerType: ContainerType, outDiagnostics: ^^IBlob) -> ^TypeReflection,
        getDynamicType                          : proc "system" (this: ^ISession) -> ^TypeReflection,
        getTypeRTTIMangledName                  : proc "system" (this: ^ISession, type: ^TypeReflection, outNameBlob: ^^IBlob) -> Result,
        getTypeConformanceWitnessMangledName    : proc "system" (this: ^ISession, type: ^TypeReflection, interfaceType: ^TypeReflection, outNameBlob: ^^IBlob) -> Result,
        getTypeConformanceWitnessSequentialID   : proc "system" (this: ^ISession, type: ^TypeReflection, interfaceType: ^TypeReflection, outId: ^u32) -> Result,
        createCompileRequest                    : proc "system" (this: ^ISession, outCompileRequest: ^^ICompileRequest) -> Result,
        createTypeConformanceComponentType      : proc "system" (this: ^ISession, type: ^TypeReflection, interfaceType: ^TypeReflection, outConformance: ^^ITypeConformance, conformanceIdOverride: int, outDiagnostics: ^^IBlob) -> Result,
        loadModuleFromIRBlob                    : proc "system" (this: ^ISession, moduleName: cstring, path: cstring, source: ^IBlob, outDiagnostics: ^^IBlob) -> ^IModule,
        getLoadedModuleCount                    : proc "system" (this: ^ISession) -> int,
        getLoadedModule                         : proc "system" (this: ^ISession, index: int) -> ^IModule,
        isBinaryModuleUpToDate                  : proc "system" (this: ^ISession, modulePath: cstring, binaryModuleBlob: ^IBlob) -> bool,
        loadModuleFromSourceString              : proc "system" (this: ^ISession, moduleName, path, str: cstring, outDiagnostics: ^^IBlob) -> ^IModule,
        getDynamicObjectRTTIBytes               : proc "system" (this: ^ISession, type: ^TypeReflection, interfaceType: ^TypeReflection, outRTTIDataBuffer: ^u32, bufferSizeInBytes: u32) -> Result,
        loadModuleInfoFromIRBlob                : proc "system" (this: ^ISession, source: ^IBlob, outModuleVersion: ^int, outModuleCompilerVersion: ^cstring, outModuleName: ^cstring) -> Result,
    },
}

IGlobalSession :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^struct {
        using iunknown_vtable: IUnknown_VTable,
        createSession                       : proc "system" (this: ^IGlobalSession, #by_ptr desc: SessionDesc, outSession: ^^ISession) -> Result,
        findProfile                         : proc "system" (this: ^IGlobalSession, name: cstring) -> ProfileID,
        setDownstreamCompilerPath           : proc "system" (this: ^IGlobalSession, passThrough: PassThrough, path: cstring),
        setDownstreamCompilerPrelude        : proc "system" (this: ^IGlobalSession, passThrough: PassThrough, preduleText: cstring),
        getDownstreamCompilerPrelude        : proc "system" (this: ^IGlobalSession, passThrough: PassThrough, outPrelude: ^^IBlob),
        getBuildTagString                   : proc "system" (this: ^IGlobalSession) -> cstring,
        setDefaultDownstreamCompiler        : proc "system" (this: ^IGlobalSession, sourceLanguage: SourceLanguage, defaultCompiler: PassThrough) -> Result,
        getDefaultDownstreamCompiler        : proc "system" (this: ^IGlobalSession, sourceLanguage: SourceLanguage) -> PassThrough,
        setLanguagePrelude                  : proc "system" (this: ^IGlobalSession, sourceLanguage: SourceLanguage, preludeText: cstring),
        getLanguagePrelude                  : proc "system" (this: ^IGlobalSession, sourceLanguage: SourceLanguage, outPrelude: ^^IBlob),
        createCompileRequest                : proc "system" (this: ^IGlobalSession, outCompilerRequest: ^^rawptr) -> Result,
        addBuiltins                         : proc "system" (this: ^IGlobalSession, sourcePath: cstring, sourceString: cstring),
        setSharedLibraryLoader              : proc "system" (this: ^IGlobalSession, loader: ^ISharedLibraryLoader),
        getSharedLibraryLoader              : proc "system" (this: ^IGlobalSession) -> ^ISharedLibraryLoader,
        checkCompileTargetSupport           : proc "system" (this: ^IGlobalSession, target: CompileTarget) -> Result,
        checkPassThroughSupport             : proc "system" (this: ^IGlobalSession, passThrough: PassThrough) -> Result,
        compileCoreModule                   : proc "system" (this: ^IGlobalSession, flags: bit_set[CompileCoreModuleFlag]) -> Result,
        loadCoreModule                      : proc "system" (this: ^IGlobalSession, coreModule: rawptr, coreModuleSizeInBytes: uint) -> Result,
        saveCoreModule                      : proc "system" (this: ^IGlobalSession, archiveType: ArchiveType, outBlob: ^^IBlob) -> Result,
        findCapability                      : proc "system" (this: ^IGlobalSession, name: cstring) -> CapabilityID,
        setDownstreamCompilerForTransition  : proc "system" (this: ^IGlobalSession, source: CompileTarget, target: CompileTarget, compiler: PassThrough),
        getDownstreamCompilerForTransition  : proc "system" (this: ^IGlobalSession, source, target: CompileTarget) -> PassThrough,
        getCompilerElapsedTime              : proc "system" (this: ^IGlobalSession, outTotalTime, outDownstreamTime: ^f64),
        setSPIRVCoreGrammar                 : proc "system" (this: ^IGlobalSession, jsonPath: cstring) -> Result,
        parseCommandLineArguments           : proc "system" (this: ^IGlobalSession, argc: i32, argv: [^]cstring, outSessionDesc: ^SessionDesc, outAuxAllocation: ^^IUnknown) -> Result,
        getSessionDescDigest                : proc "system" (this: ^IGlobalSession, sessionDesc: ^SessionDesc, outBlob: ^^IBlob) -> Result,
        compileBuiltinModule                : proc "system" (this: ^IGlobalSession, module: BuiltinModuleName, flags: bit_set[CompileCoreModuleFlag]) -> Result,
        loadBuiltinModule                   : proc "system" (this: ^IGlobalSession, module: BuiltinModuleName, moduleData: rawptr, sizeInBytes: uint) -> Result,
        saveBuiltinModule                   : proc "system" (this: ^IGlobalSession, module: BuiltinModuleName, outBlob: ^^IBlob) -> Result,
    },
}

IModule :: struct #raw_union {
    #subtype icomponenttype: IComponentType,
    using vtable: ^struct {
        using icomponenttype_vtable: IComponentType_VTable,
        findEntryPointByName     : proc "system" (this: ^IModule, name: cstring, outEntryPoint: ^^IEntryPoint) -> Result,
        getDefinedEntryPointCount: proc "system" (this: ^IModule) -> i32,
        getDefinedEntryPoint     : proc "system" (this: ^IModule, index: i32, outEntryPoint: ^^IEntryPoint) -> Result,
        serialize                : proc "system" (this: ^IModule, outSerializedBlob: ^^IBlob) -> Result,
        writeToFile              : proc "system" (this: ^IModule, fileName: cstring) -> Result,
        getName                  : proc "system" (this: ^IModule) -> cstring,
        getFilePath              : proc "system" (this: ^IModule) -> cstring,
        getUniqueIdentity        : proc "system" (this: ^IModule) -> cstring,
        findAndCheckEntryPoint   : proc "system" (this: ^IModule, name: cstring, stage: Stage, outEntryPoint: ^^IEntryPoint, outDiagnostics: ^^IBlob) -> Result,
        getDependencyFileCount   : proc "system" (this: ^IModule) -> i32,
        getDependencyFilePath    : proc "system" (this: ^IModule, index: i32) -> cstring,
        getModuleReflection      : proc "system" (this: ^IModule) -> ^DeclReflection,
        disassemble              : proc "system" (this: ^IModule, outDisassembledBlob: ^^IBlob) -> Result,
    },
}

IComponentType :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^IComponentType_VTable,
}

IComponentType_VTable :: struct {
    using iunknown_vtable: IUnknown_VTable,
    getSession                 : proc "system" (this: ^IComponentType) -> ^ISession,
    getLayout                  : proc "system" (this: ^IComponentType, targetIndex: int, outDiagnostics: ^^IBlob) -> ^ProgramLayout,
    getSpecializationParamCount: proc "system" (this: ^IComponentType) -> int,
    getEntryPointCode          : proc "system" (this: ^IComponentType, entryPointIndex: int, targetIndex: int, outCode: ^^IBlob, outDiagnostics: ^^IBlob) -> Result,
    getResultAsFileSystem      : proc "system" (this: ^IComponentType, entryPointIndex: int, targetIndex: int, outFileSystem: ^^IMutableFileSystem) -> Result,
    getEntryPointHash          : proc "system" (this: ^IComponentType, entryPointIndex, targetIndex: int, outHash: ^^IBlob) -> Result,
    specialize                 : proc "system" (this: ^IComponentType, specializationArgs: [^]SpecializationArg, specializationArgCount: int, outSpecializedComponentType: ^^IComponentType, outDiagnostics: ^^IBlob) -> Result,
    link                       : proc "system" (this: ^IComponentType, outLinkedComponentType: ^^IComponentType, outDiagnostics: ^^IBlob) -> Result,
    getEntryPointHostCallable  : proc "system" (this: ^IComponentType, entryPointIndex, targetIndex: i32, outSharedLibrary: ^^ISharedLibrary, outDiagnostics: ^^IBlob) -> Result,
    renameEntryPoint           : proc "system" (this: ^IComponentType, newName: cstring, outEntryPoint: ^^IComponentType) -> Result,
    linkWithOptions            : proc "system" (this: ^IComponentType, outLinkedComponentType: ^^IComponentType, compilerOptionEntryCount: u32, compilerOptionEntries: [^]CompilerOptionEntry, outDiagnostics: ^^IBlob) -> Result,
    getTargetCode              : proc "system" (this: ^IComponentType, targetIndex: int, outCode: ^^IBlob, outDiagnostics: ^^IBlob) -> Result,
    getTargetMetadata          : proc "system" (this: ^IComponentType, targetIndex: int, outMetadata: ^^IMetadata, outDiagnostics: ^^IBlob) -> Result,
    getEntryPointMetadata      : proc "system" (this: ^IComponentType, entryPointIndex: int, targetIndex: int, outMetadata: ^^IMetadata, outDiagnostics: ^^IBlob) -> Result,
}

IEntryPoint :: struct #raw_union {
    #subtype icomponenttype: IComponentType,
    using vtable: ^struct {
        using icomponenttype_vtable: IComponentType_VTable,
        getFunctionReflection: proc "system" (this: ^IEntryPoint) -> ^FunctionReflection,
    },
}

IMetadata :: struct #raw_union {
    #subtype icastable: ICastable,
    using vtable: ^struct {
        using icastable_vtable: ICastable_VTable,
        isParameterLocationUsed: proc "system" (this: ^IMetadata, category: ParameterCategory, spaceIndex, registerIndex: uint, outUsed: ^bool) -> Result,
        getDebugBuildIdentifier: proc "system" (this: ^IMetadata) -> cstring,
    },
}

ISharedLibrary :: struct #raw_union {
    #subtype icastable: ICastable,
    using vtable: ^struct {
        using icastable_vtable: ICastable_VTable,
        findSymbolByName: proc "system" (this: ^ISharedLibrary, name: cstring) -> rawptr,
    },
}

ISharedLibraryLoader :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^struct {
        using iunknown_vtable: IUnknown_VTable,
        loadSharedLibrary: proc "system" (this: ^ISharedLibraryLoader, path: cstring, sharedLibraryOut: ^^ISharedLibrary) -> Result,
    },
}

ITypeConformance :: struct #raw_union {
    #subtype icomponenttype: IComponentType,
    using vtable: ^struct {
        using icomponenttype_vtable: IComponentType_VTable,
    },
}

IMutableFileSystem :: struct #raw_union {
    #subtype ifilesystext: IFileSystemExt,
    using vtable: ^struct {
        using ifilesystemext_vtable: IFileSystemExt_VTable,
        saveFile       : proc "system" (this: ^IMutableFileSystem, path: cstring, data: rawptr, size: uint) -> Result,
        saveFileBlob   : proc "system" (this: ^IMutableFileSystem, path: cstring, dataBlob: ^IBlob) -> Result,
        remove         : proc "system" (this: ^IMutableFileSystem, path: cstring) -> Result,
        createDirectory: proc "system" (this: ^IMutableFileSystem, path: cstring) -> Result,
    },
}

IFileSystemExt :: struct #raw_union {
    #subtype ifilesystem: IFileSystem,
    using vtable: ^IFileSystemExt_VTable,
}

IFileSystemExt_VTable :: struct {
    using ifilesystem_vtable: IFileSystem_VTable,
    getFileUniqueIdentity: proc "system" (this: ^IFileSystemExt, path: cstring, outUniqueIdentity: ^^IBlob) -> Result,
    calcCombinedPath     : proc "system" (this: ^IFileSystemExt, fromPath, path: cstring, pathOut: ^^IBlob) -> Result,
    getPathType          : proc "system" (this: ^IFileSystemExt, path: cstring, pathTypeOut: ^PathType) -> Result,
    getPath              : proc "system" (this: ^IFileSystemExt, path: cstring, outPath: ^^IBlob) -> Result,
    clearCache           : proc "system" (this: ^IFileSystemExt),
    enumeratePathContents: proc "system" (this: ^IFileSystemExt, path: cstring, callback: FileSystemContentsCallback, userData: rawptr) -> Result,
    getOSPathKind        : proc "system" (this: ^IFileSystemExt) -> OSPathKind,
}

FileSystemContentsCallback :: #type proc(pathType: PathType, name: cstring, userData: rawptr)

OSPathKind :: enum u8 {
    None,
    Direct,
    OperatingSystem,
}

PathType :: enum u32 {
    DIRECTORY,
    FILE,
}

IFileSystem :: struct #raw_union {
    #subtype icastable: ICastable,
    using vtable: ^IFileSystem_VTable,
}

IFileSystem_VTable :: struct {
    using icastable_vtable: ICastable_VTable,
    loadFile: proc "system" (this: ^IFileSystem, path: cstring, outBlob: ^^IBlob) -> Result,
}

IBlob :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^struct {
        using iunknown_vtable: IUnknown_VTable,
        getBufferPointer: proc "system" (this: ^IBlob) -> rawptr,
        getBufferSize   : proc "system" (this: ^IBlob) -> uint,
    },
}

IUnknown :: struct {
    using vtable: ^IUnknown_VTable,
}

IUnknown_VTable :: struct {
    queryinterface: proc "system" (this: ^IUnknown, #by_ptr uuid: UUID, outObject: ^rawptr) -> Result,
    addRef        : proc "system" (this: ^IUnknown) -> u32,
    release       : proc "system" (this: ^IUnknown) -> u32,
}


ICastable :: struct #raw_union {
    #subtype iunknown: IUnknown,
    using vtable: ^ICastable_VTable,
}

ICastable_VTable :: struct {
    using iunknown_vtable: IUnknown_VTable,
    castAs: proc "system" (this: ^ICastable, #by_ptr guid: UUID) -> rawptr,
}
