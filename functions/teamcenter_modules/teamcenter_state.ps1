# ============================================================
# ESTADO COMPARTILHADO DA INTEGRACAO COM O TEAMCENTER
# ============================================================
# Objetos reutilizados somente durante a execucao atual:
#   ImporterAssembly: assembly principal do Importar GD;
#   TeamcenterSession: sessao autenticada;
#   TeamcenterFunctions: tipo ImportarGD.Controller.Functions;
#   TeamcenterEnvironment: ambiente Teste ou Processo;
#   TeamcenterMethodCache: cache dos MethodInfo localizados;
#   TeamcenterQueryAssemblies: assemblies usados pelas Saved Queries.
# ============================================================

$script:ImporterAssembly = $null
$script:TeamcenterSession = $null
$script:TeamcenterFunctions = $null
$script:TeamcenterEnvironment = $null

$script:TeamcenterMethodCache = [System.Collections.Generic.Dictionary[string, object]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

$script:TeamcenterQueryAssemblies = [System.Collections.Generic.List[object]]::new()