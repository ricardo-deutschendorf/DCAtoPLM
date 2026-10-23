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
#   Assemblies SOA utilizados pelas Saved Queries.
# ============================================================

$script:ImporterAssembly =
$null

$script:TeamcenterSession =
$null

$script:TeamcenterFunctions =
$null

$script:TeamcenterEnvironment =
$null

$script:TeamcenterQueryAssemblies =
[System.Collections.Generic.List[object]]::new()