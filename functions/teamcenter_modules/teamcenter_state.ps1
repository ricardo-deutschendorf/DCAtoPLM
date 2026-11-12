# ============================================================
# ESTADO COMPARTILHADO DA INTEGRACAO COM O TEAMCENTER
# ============================================================
#
# As variaveis abaixo armazenam os objetos reutilizados durante
# a execucao atual. Nenhum objeto e mantido entre execucoes.
#
# ImporterAssembly:
#   Assembly principal carregado do executavel Importar GD.
#
# TeamcenterSession:
#   Sessao autenticada no ambiente configurado.
#
# TeamcenterFunctions:
#   Tipo estatico ImportarGD.Controller.Functions.
#
# TeamcenterEnvironment:
#   Ambiente atualmente conectado: Teste ou Processo.
#
# TeamcenterQueryAssemblies:
#   Lista dos assemblies SOA utilizados pelas Saved Queries.
#   A lista e reinicializada durante o carregamento das bibliotecas.
# ============================================================

$script:ImporterAssembly =
$null

$script:TeamcenterSession =
$null

$script:TeamcenterFunctions =
$null

$script:TeamcenterEnvironment =
$null

# TeamcenterMethodCache:
#   Armazena os MethodInfo ja localizados no tipo
#   ImportarGD.Controller.Functions durante a execucao atual.
$script:TeamcenterMethodCache =
[System.Collections.Generic.Dictionary[string, object]]::new(
  [System.StringComparer]::OrdinalIgnoreCase
)

$script:TeamcenterQueryAssemblies =
[System.Collections.Generic.List[object]]::new()
