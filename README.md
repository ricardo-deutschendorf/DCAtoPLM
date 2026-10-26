DCAtoPLM

[!WARNING]

A criação de Items e revisões, o processamento em lote, a pesquisa no PDM, a pesquisa por pastas, a preparação dos PDFs e a solicitação de workflows estão implementados.

O comportamento final da importação depende do assembly de integração do Teamcenter instalado e das configurações de cada ambiente.

Valide todo o processo em um ambiente controlado antes de utilizar a aplicação em produção.

O DCAtoPLM importa documentos PDF de um Vault DCA do SOLIDWORKS PDM para o Siemens Teamcenter.

A aplicação pesquisa a estrutura de documentação configurada, interpreta os dados dos documentos pelo nome dos arquivos e pelos cartões do PDM, prepara um plano de importação, cria os objetos necessários no Teamcenter, importa o PDF como Dataset e, quando aplicável, solicita um workflow de acordo com o estado atual do documento no PDM.

A aplicação suporta:

pesquisas individuais;
várias pesquisas na mesma execução;
seleção de vários documentos;
pesquisa por nome completo de pasta;
importação completa de pastas;
seleção individual dos documentos de uma pasta;
criação de novos Items e revisões no Teamcenter;
importação de Dataset em revisões existentes;
execução em modo Preview;
continuação do lote após falhas individuais.

[!IMPORTANT]

A integração foi desenvolvida para o Siemens Teamcenter 2312.

Outras versões podem funcionar, mas a compatibilidade ainda não foi confirmada.

Os objetos de negócio, propriedades, serviços, workflows e assemblies de integração do Teamcenter variam entre ambientes e devem ser revisados antes do uso.

Funcionalidades principais
SOLIDWORKS PDM
Pesquisa PDFs através da API do SOLIDWORKS PDM.
Utiliza o sistema de arquivos como alternativa quando a API não está disponível.
Reutiliza a conexão com o Vault durante a mesma execução.
Permite autenticação por arquivo protegido de credenciais.
Utiliza LoginAuto quando não existe um arquivo de credenciais válido.
Solicita uma cópia local quando o arquivo ainda não está disponível no cache.
Consulta o estado atual do documento no workflow do PDM.
Lê revisão e descrição diretamente do cartão de dados.
Prioriza os dados do cartão sobre os valores extraídos do nome do arquivo.
Permite descobrir e exibir todas as variáveis disponíveis no cartão.
Pesquisa e seleção
Realiza pesquisas parciais sem exigir *.
Aceita curingas * e ? nas pesquisas por código.
Aceita várias pesquisas separadas por vírgulas.
Remove termos repetidos antes da execução.
Permite selecionar um resultado, vários resultados, um intervalo ou todos.
Pesquisa pastas pelo nome completo.
Importa todos os PDFs válidos de uma pasta.
Permite abrir uma pasta e selecionar documentos individualmente.
Impede que o mesmo caminho seja adicionado mais de uma vez ao lote.
Teamcenter
Conecta ao ambiente de Teste ou Processo configurado.
Cria Items e primeiras revisões.
Mapeia cada tipo de documento para os objetos de negócio correspondentes.
Importa PDFs como Datasets nas revisões criadas.
Importa PDFs como Datasets em revisões existentes.
Valida antecipadamente os destinos de documentos DatasetOnly.
Solicita workflows de aprovação ou obsolescência.
Continua processando o lote após falhas individuais.
Apresenta um plano antes de alterar o Teamcenter.
Apresenta um resumo final do lote.
Retorna um código de saída indicando sucesso ou falha.
Diagnóstico e validação
Valida os arquivos de funções antes da pesquisa.
Confirma que todas as funções obrigatórias foram carregadas.
Possui modo Preview sem alterações no Teamcenter.
Possui modo detalhado para diagnóstico.
Exibe caminhos, variáveis do cartão, resultados de consultas e stacks de erro.
Valida o PDF temporário por caminho, extensão, tamanho e acesso de leitura.
Categorias de documentos suportadas
Desenho Original DCA

Pasta de origem:

Plain Text
Desenhos Originais

Tipo interno:

Plain Text
Original

Comportamento:

cria um novo Item no Teamcenter;
cria a primeira revisão;
importa o PDF como Dataset;
pode solicitar workflow conforme o estado do PDM.
Processo DCA

Pasta de origem:

Plain Text
FP - Ficha de Processo (PDF)

Tipo interno:

Plain Text
Processo

Comportamento:

cria um novo Item no Teamcenter;
cria a primeira revisão;
importa o PDF como Dataset;
pode solicitar workflow conforme o estado do PDM.
Norma Externa DCA

Pasta de origem:

Plain Text
Normas Externas

Tipo interno:

Plain Text
NormaExterna

Comportamento:

interpreta o código técnico da norma;
separa o código da descrição quando possível;
cria um novo Item no Teamcenter;
cria a primeira revisão;
importa o PDF como Dataset;
pode solicitar workflow conforme o estado do PDM.
XXRE Dimensional

Pasta de origem:

Plain Text
FP - XXRE Dimensional

Tipo interno:

Plain Text
DatasetOnly

Comportamento:

não cria um novo Item;
não cria uma nova revisão;
procura um Item e uma revisão existentes;
valida o destino antes da confirmação final;
importa somente o PDF como Dataset;
não solicita workflow.

Cada categoria utiliza uma configuração específica do Teamcenter.

Os mapeamentos podem ser diferentes entre os ambientes de Teste e Processo.

Estados de workflow suportados

O DCAtoPLM consulta o estado atual de cada arquivo no SOLIDWORKS PDM.

Os seguintes estados podem solicitar workflows no Teamcenter:

Aprovado

Solicita o workflow configurado em:

Plain Text
DCA_TC_APPROVED_WORKFLOW
Obsoleto

Solicita o workflow configurado em:

Plain Text
DCA_TC_OBSOLETE_WORKFLOW
Outros estados

O Item e o PDF são processados sem solicitação automática de workflow.

Documentos do tipo DatasetOnly nunca solicitam workflow.

A solicitação ocorre somente depois que o método de importação do PDF termina sem exceção.

[!NOTE]

Uma chamada sem exceção confirma que a solicitação foi enviada ao assembly de integração.

A execução final do workflow, seus handlers, status de liberação e conclusão dependem da configuração do ambiente Teamcenter.

Estrutura do repositório
Plain Text
DCAtoPLM/
├── import_dcaPdfToTeamcenter.ps1
├── start_DCAtoPLM.bat
├── .env.example
├── .env
├── README.md
└── functions/
├── output_functions.ps1
├── pdm_modules/
│ ├── pdm_connection.ps1
│ ├── pdm_files.ps1
│ ├── pdm_filename_parser.ps1
│ ├── pdm_card_reader.ps1
│ └── pdm_document_metadata.ps1
├── import_plan_modules/
│ ├── import_pdf_preparation.ps1
│ ├── import_search_input.ps1
│ └── import_plan_display.ps1
├── search_modules/
│ ├── search_folder_documents.ps1
│ ├── search_folder_navigation.ps1
│ ├── search_folder_selection.ps1
│ ├── search_folder_lookup.ps1
│ └── search_code_lookup.ps1
└── teamcenter_modules/
├── teamcenter_state.ps1
├── teamcenter_connections.ps1
├── teamcenter_query_diagnostics.ps1
├── teamcenter_query_properties.ps1
├── teamcenter_item_lookup.ps1
├── teamcenter_dataset.ps1
├── teamcenter_creation_helpers.ps1
├── teamcenter_creation.ps1
└── teamcenter_workflow.ps1
import_dcaPdfToTeamcenter.ps1

Ponto de entrada principal da aplicação.

Responsabilidades:

carregar o arquivo .env;
carregar os arquivos de funções;
validar as funções obrigatórias;
receber a entrada da pesquisa;
coordenar a pesquisa e a seleção;
normalizar os documentos;
apresentar o resumo do lote;
conectar ao Teamcenter;
validar destinos existentes;
solicitar a confirmação final;
processar cada documento;
apresentar o resumo final;
retornar o código de saída.
functions/output_functions.ps1

Funções de saída e apresentação no console.

functions/pdm_modules

Conexão com o PDM, disponibilidade dos arquivos, interpretação dos nomes, leitura de cartões, consulta de estado e normalização dos metadados.

functions/import_plan_modules

Interpretação da entrada, montagem do plano e preparação do PDF temporário.

functions/search_modules

Pesquisa por código, pesquisa por pasta, navegação e seleção de documentos.

functions/teamcenter_modules

Conexão, consultas, localização de Items, criação, importação de Dataset e execução de workflows.

start_DCAtoPLM.bat

Inicializador recomendado para Windows.

.env.example

Modelo seguro de configuração, sem valores internos.

.env

Configuração local da aplicação. Esse arquivo não deve ser enviado ao repositório.

Requisitos

O ambiente de execução deve possuir:

Windows PowerShell compatível com os scripts;
acesso ao Siemens Teamcenter 2312;
conta do Teamcenter com as permissões necessárias;
permissão para criar os tipos de Item configurados;
permissão para criar revisões;
permissão para importar Datasets PDF;
permissão para iniciar os workflows configurados;
cliente do SOLIDWORKS PDM instalado;
acesso ao Vault configurado;
arquivo Interop.EdmLib.dll;
acesso ao cache local do PDM;
permissão para baixar arquivos do Vault;
assembly compatível de integração com o Teamcenter;
acesso à pasta temporária de PDFs.

Normalmente não é necessário executar como administrador.

Estrutura esperada do Vault

A raiz é definida por DCA_ROOT ou pelo parâmetro -SearchRoot.

Exemplo:

Plain Text
C:\VAULT_ROOT

Estrutura esperada:

Plain Text
C:\VAULT_ROOT\
└── Documentação\
├── Desenhos Originais\
│ ├── CUSTOMER_A\
│ └── CUSTOMER_B\
│
├── FP - Ficha de Processo (PDF)\
│ ├── CUSTOMER_A\
│ ├── CUSTOMER_B\
│ └── instructions\
│
├── Normas Externas\
│ ├── AMS\
│ ├── ASTM\
│ ├── MIL\
│ └── outras normas\
│
└── FP - XXRE Dimensional\
├── CUSTOMER_A\
└── CUSTOMER_B\

Somente arquivos localizados dentro de uma categoria reconhecida podem ser preparados para o Teamcenter.

Mapeamento:

Plain Text
Desenhos Originais
-> Original
 
FP - Ficha de Processo (PDF)
-> Processo
 
Normas Externas
-> NormaExterna
 
FP - XXRE Dimensional
-> DatasetOnly
Configuração

O método recomendado de configuração utiliza um arquivo .env local.

Copie:

Plain Text
.env.example

Para:

Plain Text
.env

Depois substitua os valores de exemplo pelos valores corretos da estação e do ambiente.

O arquivo .env não deve ser enviado ao repositório porque pode conter:

caminhos internos;
nomes de usuários;
senhas;
endereços de servidores;
nomes de workflows;
nomes de objetos internos;
caminhos de arquivos de credenciais.
Exemplo de configuração do ambiente
Plain Text
dotenv não tem suporte total. O realce de sintaxe é baseado em Plain Text.
# ============================================================
# DCA Vault
# ============================================================
 
DCA_ROOT=C:\VAULT_ROOT
DCA_VAULT_NAME=VAULT_NAME
DCA_PDM_LIB=C:\Path\To\Interop.EdmLib.dll
DCA_VAULT_CREDENTIAL=C:\Secure\vault-credential.xml
DCA_TEMP_FOLDER=C:\Temp\DCAtoPLM
 
# ============================================================
# Variaveis dos cartoes do PDM
# ============================================================
 
DCA_PDM_VAR_ORIGINAL_REVISION=<ORIGINAL_REVISION_VARIABLE>
DCA_PDM_VAR_PROCESS_REVISION=<PROCESS_REVISION_VARIABLE>
DCA_PDM_VAR_STANDARD_REVISION=<STANDARD_REVISION_VARIABLE>
DCA_PDM_VAR_DATASET_REVISION=<DATASET_REVISION_VARIABLE>
 
DCA_PDM_VAR_ORIGINAL_DESCRIPTION=<ORIGINAL_DESCRIPTION_VARIABLE>
DCA_PDM_VAR_PROCESS_DESCRIPTION=<PROCESS_DESCRIPTION_VARIABLE>
DCA_PDM_VAR_STANDARD_DESCRIPTION=<STANDARD_DESCRIPTION_VARIABLE>
 
DCA_PDM_DISCOVER_CARD_VARIABLES=false
 
# ============================================================
# Assembly de integracao com o Teamcenter
# ============================================================
 
DCA_IMPORTER_PATH=C:\Path\To\Importar GD.exe
 
# ============================================================
# Ambiente selecionado
# Valores permitidos: Teste ou Processo
# ============================================================
 
DCA_TC_ENV=Teste
 
# ============================================================
# Ambiente de Teste
# ============================================================
 
DCA_TC_TEST_URL=<TEAMCENTER_TEST_URL>
DCA_TC_TEST_USER=<TEAMCENTER_TEST_USER>
DCA_TC_TEST_PASSWORD=<TEAMCENTER_TEST_PASSWORD>
 
# ============================================================
# Ambiente de Processo
# ============================================================
 
DCA_TC_PROCESS_URL=<TEAMCENTER_PROCESS_URL>
DCA_TC_PROCESS_USER=<TEAMCENTER_PROCESS_USER>
DCA_TC_PROCESS_PASSWORD=<TEAMCENTER_PROCESS_PASSWORD>
 
# ============================================================
# Templates de workflow
# ============================================================
 
DCA_TC_APPROVED_WORKFLOW=<APPROVED_WORKFLOW_TEMPLATE>
DCA_TC_OBSOLETE_WORKFLOW=<OBSOLETE_WORKFLOW_TEMPLATE>
 
# ============================================================
# Objetos do ambiente de Teste
# ============================================================
 
DCA_TC_TEST_ORIGINAL_ITEM_TYPE=<ORIGINAL_ITEM_TYPE>
DCA_TC_TEST_ORIGINAL_REVISION_TYPE=<ORIGINAL_REVISION_TYPE>
DCA_TC_TEST_ORIGINAL_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_ORIGINAL_CLIENT_VALUE=<CLIENT_VALUE>
 
DCA_TC_TEST_PROCESS_ITEM_TYPE=<PROCESS_ITEM_TYPE>
DCA_TC_TEST_PROCESS_REVISION_TYPE=<PROCESS_REVISION_TYPE>
DCA_TC_TEST_PROCESS_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_PROCESS_CLIENT_VALUE=<CLIENT_VALUE>
 
DCA_TC_TEST_STANDARD_ITEM_TYPE=<STANDARD_ITEM_TYPE>
DCA_TC_TEST_STANDARD_REVISION_TYPE=<STANDARD_REVISION_TYPE>
DCA_TC_TEST_STANDARD_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_TEST_STANDARD_CLIENT_VALUE=<CLIENT_VALUE>
 
# ============================================================
# Objetos do ambiente de Processo
# ============================================================
 
DCA_TC_PROCESS_ORIGINAL_ITEM_TYPE=<ORIGINAL_ITEM_TYPE>
DCA_TC_PROCESS_ORIGINAL_REVISION_TYPE=<ORIGINAL_REVISION_TYPE>
DCA_TC_PROCESS_ORIGINAL_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_ORIGINAL_CLIENT_VALUE=<CLIENT_VALUE>
 
DCA_TC_PROCESS_PROCESS_ITEM_TYPE=<PROCESS_ITEM_TYPE>
DCA_TC_PROCESS_PROCESS_REVISION_TYPE=<PROCESS_REVISION_TYPE>
DCA_TC_PROCESS_PROCESS_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_PROCESS_CLIENT_VALUE=<CLIENT_VALUE>
 
DCA_TC_PROCESS_STANDARD_ITEM_TYPE=<STANDARD_ITEM_TYPE>
DCA_TC_PROCESS_STANDARD_REVISION_TYPE=<STANDARD_REVISION_TYPE>
DCA_TC_PROCESS_STANDARD_CLIENT_PROPERTY=<CLIENT_PROPERTY>
DCA_TC_PROCESS_STANDARD_CLIENT_VALUE=<CLIENT_VALUE>

Mais de uma variável de revisão pode ser configurada utilizando | ou ;.

Exemplo:

Plain Text
dotenv não tem suporte total. O realce de sintaxe é baseado em Plain Text.
DCA_PDM_VAR_PROCESS_REVISION=Revisao|Revision|REV

As variáveis são testadas na ordem configurada.

Executando a aplicação
Inicializador recomendado

Execute:

BAT
start_DCAtoPLM.bat
Execução direta pelo PowerShell
PowerShell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
-File .\import_dcaPdfToTeamcenter.ps1
Pesquisa por parâmetro
PowerShell
.\import_dcaPdfToTeamcenter.ps1 `
-SourceCode "AMS 22"
Várias pesquisas
PowerShell
.\import_dcaPdfToTeamcenter.ps1 `
-SourceCode "1000359,1000359-2,AMS 2248"
Modo Preview
PowerShell
.\import_dcaPdfToTeamcenter.ps1 `
-SourceCode "AMS 22" `
-Preview

O modo Preview executa:

pesquisa;
seleção;
interpretação do nome;
leitura dos cartões;
normalização dos metadados;
preparação do lote;
apresentação do plano.

O modo Preview não executa:

conexão com o Teamcenter;
criação de Items;
criação de revisões;
importação de PDFs;
solicitação de workflows.
Saída detalhada
PowerShell
.\import_dcaPdfToTeamcenter.ps1 `
-SourceCode "AMS 22" `
-Preview `
-Details `
-OutputDelayMilliseconds 0

O parâmetro -Details exibe:

caminhos completos;
variáveis do cartão;
campos configurados;
resultados das consultas;
propriedades da revisão;
templates de workflow;
detalhes dos arquivos temporários;
arquivos e linhas de erros;
stack de chamadas.
Pesquisa somente no sistema de arquivos
PowerShell
.\import_dcaPdfToTeamcenter.ps1 `
-SourceCode "1000359" `
-NoVaultApi

Nesse modo, a API do PDM não é utilizada.

Somente arquivos disponíveis localmente serão pesquisados.

Parâmetros
-SearchRoot

Tipo:

Plain Text
string

Padrão:

Plain Text
DCA_ROOT

Define a raiz da estrutura do Vault DCA.

-SourceCode

Tipo:

Plain Text
string

Aceita códigos, padrões com curingas e pesquisas por pasta.

Vários termos podem ser separados por vírgulas.

-ItemName

Tipo:

Plain Text
string

Define um nome inicial opcional para o Item.

A descrição do cartão possui prioridade sobre esse valor.

-VaultName

Tipo:

Plain Text
string

Padrão:

Plain Text
DCA_VAULT_NAME

Define o nome do Vault do SOLIDWORKS PDM.

-PdmLibraryPath

Tipo:

Plain Text
string

Padrão:

Plain Text
DCA_PDM_LIB

Define o caminho de Interop.EdmLib.dll.

-VaultCredentialPath

Tipo:

Plain Text
string

Padrão:

Plain Text
DCA_VAULT_CREDENTIAL

Define o caminho do arquivo protegido de credenciais.

-OutputDelayMilliseconds

Tipo:

Plain Text
integer

Padrão:

Plain Text
10

Intervalo permitido:

Plain Text
0 a 2000
-NoVaultApi

Pesquisa somente arquivos disponíveis localmente.

-Details

Exibe caminhos e informações técnicas adicionais.

-Preview

Prepara e apresenta o lote sem modificar o Teamcenter.

Pesquisa por código
Pesquisa parcial automática

As pesquisas por código são parciais por padrão.

Ao informar:

Plain Text
AMS 22

Podem ser encontrados valores como:

Plain Text
AMS 2241
AMS 2242
AMS 2248
AMS 2261
AMS 2262

Não é necessário incluir * em pesquisas parciais comuns.

Curingas explícitos

Exemplos:

Plain Text
AMS 22*
*2248*
BR50??A-00

Curingas suportados:

Plain Text
* corresponde a zero ou mais caracteres
? corresponde a um caractere

Os curingas são permitidos nas pesquisas por código, mas não nas pesquisas por pasta.

Várias pesquisas

Separe os termos por vírgulas:

Plain Text
1000359,1000359-2,AMS 2248

Cada termo será pesquisado independentemente.

Termos repetidos são removidos antes da execução.

Seleção de vários resultados

Quando mais de um PDF for encontrado, são aceitas as seguintes entradas:

Plain Text
1
1,2,4
1-5
T
TODOS

Significado:

1 seleciona um resultado;
1,2,4 seleciona vários resultados;
1-5 seleciona um intervalo;
T seleciona todos;
TODOS seleciona todos.

Quando apenas um resultado é encontrado, ele é selecionado automaticamente.

Pesquisa por pasta

A pesquisa por pasta exige o nome completo da pasta.

Não são aceitos curingas ou nomes parciais.

Importar todos os documentos da pasta

Utilize uma barra inicial:

Plain Text
\NomeCompleto

Exemplo:

Plain Text
\HSRE DIMENSIONAL

Esse modo localiza a pasta exata e retorna seus PDFs válidos sem seleção individual.

Selecionar documentos da pasta

Utilize duas barras iniciais:

Plain Text
\\NomeCompleto

Exemplo:

Plain Text
\\HSRE DIMENSIONAL

Esse modo localiza a pasta exata e abre a seleção individual dos documentos.

Também são aceitas barras comuns:

Plain Text
/NomeCompleto
//NomeCompleto

A entrada é normalizada internamente.

Restrições

Pesquisas por pasta não aceitam:

Plain Text
*
?
..
 

Caracteres inválidos para caminhos também são bloqueados.

Cartões de dados do PDM

A aplicação pode ler revisão e descrição no cartão do PDM.

Prioridade da revisão

A revisão pode ser extraída inicialmente do nome do arquivo.

Quando o cartão possui uma revisão configurada e preenchida, ela substitui o valor extraído do nome.

A aplicação preserva:

revisão encontrada no nome;
revisão final;
origem da revisão final.

A origem pode ser:

Plain Text
nome do arquivo
cartao de dados
Prioridade da descrição

A descrição inicial pode vir:

do nome do PDF;
do parâmetro -ItemName;
do código, em importações por pasta sem descrição.

Quando uma descrição válida é encontrada no cartão, ela substitui o valor anterior.

Normalização da descrição de Desenho Original

A descrição de um Desenho Original passa pelas seguintes normalizações:

remoção de vírgulas usadas como separadores;
remoção de espaços duplicados;
primeira letra em maiúsculo;
demais caracteres em minúsculo.
Descoberta das variáveis do cartão

Para exibir todas as variáveis disponíveis, configure temporariamente:

Plain Text
dotenv não tem suporte total. O realce de sintaxe é baseado em Plain Text.
DCA_PDM_DISCOVER_CARD_VARIABLES=true

Execute com:

PowerShell
-Details

A saída apresentará:

nome da variável;
ID, quando disponível;
valor;
método de leitura utilizado.

Depois de identificar os campos corretos, desative:

PowerShell
dotenv não tem suporte total. O realce de sintaxe é baseado em PowerShell.
DCA_PDM_DISCOVER_CARD_VARIABLES=false
Plano de importação

Antes de alterar o Teamcenter, a aplicação apresenta um plano.

O plano contém:

ambiente selecionado;
servidor, no modo Details;
quantidade de documentos;
tipo do Item;
tipo da revisão;
propriedade e valor do cliente;
identificador da revisão;
estado do PDM;
workflow previsto;
template do workflow, no modo Details;
erros de configuração;
caminho do arquivo, no modo Details.

A aplicação avisa quando:

a configuração do tipo é inválida;
um workflow não está configurado;
algum documento não poderá ser criado;
o Item e o PDF serão mantidos sem workflow.
Fluxos de processamento no Teamcenter
Criação de Item

Os seguintes tipos utilizam esse fluxo:

Plain Text
Original
Processo
NormaExterna

Para cada documento, a aplicação:

cria o Item;
obtém o objeto criado;
obtém ou localiza a revisão;
valida o tipo técnico da revisão;
garante que o PDF esteja disponível localmente;
cria uma cópia temporária validada;
importa o PDF como Dataset;
determina o workflow pelo estado do PDM;
solicita o workflow quando aplicável;
registra o resultado individual.
Dataset em revisão existente

O tipo abaixo utiliza esse fluxo:

Plain Text
DatasetOnly

Antes da confirmação final, a aplicação:

conecta ao Teamcenter;
procura o Item existente;
procura a revisão esperada;
armazena os objetos encontrados;
valida todos os destinos do lote.

Se um destino DatasetOnly não for encontrado, a execução é interrompida antes da confirmação final.

Durante o processamento:

reutiliza o Item e a revisão existentes;
garante que o PDF esteja disponível;
cria uma cópia temporária validada;
importa o PDF como Dataset;
não cria Item;
não cria revisão;
não solicita workflow;
registra o resultado individual.
Preparação do PDF

Antes de chamar o importador, a aplicação:

confirma que o caminho de origem existe;
confirma que a extensão é .pdf;
rejeita arquivos vazios;
valida DCA_TEMP_FOLDER;
cria a pasta temporária quando necessário;
normaliza o código do Item para uso no nome do arquivo;
remove uma cópia temporária anterior;
copia o PDF;
confirma que a cópia existe;
compara o tamanho da origem e da cópia;
abre a cópia para leitura;
retorna o caminho validado.

O PDF original não é modificado.

Caracteres inválidos para nomes de arquivos no Windows são substituídos por _.

Exemplo:

Plain Text
C:\Temp\DCAtoPLM\1000359-2.pdf
Importação do PDF

O assembly de integração deve possuir um método compatível com:

Plain Text
ImportarPDF(
DatasetId,
DatasetRev,
pathArquivo,
ItemRevision,
Sobrepor
)

Os parâmetros e o comportamento exato dependem do assembly instalado.

[!CAUTION]

Os requisitos do nome e da revisão do Dataset devem ser confirmados no assembly utilizado pelo ambiente Teamcenter.

Valores incompatíveis podem permitir a criação do Item sem que o PDF seja anexado corretamente.

A aplicação considera a chamada concluída quando o método retorna sem exceção.

Sem uma consulta posterior da relação no Teamcenter, isso não confirma de forma independente que o Dataset foi relacionado corretamente.

Workflows do Teamcenter

Após a importação do PDF, a aplicação pode chamar um método compatível com:

Plain Text
Start_Workflow(
Workflow_Template,
Revisions
)

Mapeamento:

Plain Text
Aprovado
-> DCA_TC_APPROVED_WORKFLOW
 
Obsoleto
-> DCA_TC_OBSOLETE_WORKFLOW

Outros estados, como:

Plain Text
Verificado
Em elaboracao
Em verificacao

não solicitam workflow automaticamente.

O template precisa:

existir no Teamcenter;
estar acessível para o usuário conectado;
aceitar o tipo de revisão enviado;
possuir handlers válidos no ambiente.
Resultados individuais
Item e PDF importados

O Item foi criado e o método de importação do PDF foi concluído.

Quando aplicável, o resultado também informa que o workflow foi solicitado.

Item criado, mas PDF não importado

O Item foi criado, mas uma etapa posterior de preparação ou importação falhou.

Essa condição pode deixar um Item sem Dataset e precisa ser revisada manualmente.

Item não criado

A criação do Item ou a validação da revisão falhou antes da importação do PDF.

Dataset importado em revisão existente

O Item e a revisão foram encontrados e o método de importação foi concluído.

Dataset não importado em revisão existente

O destino não foi encontrado ou alguma etapa de preparação ou importação falhou.

Códigos de saída
Código 0

Retornado quando:

todos os documentos foram processados com sucesso;
o modo Preview foi concluído;
o usuário cancelou antes das alterações no Teamcenter.
Código 1

Retornado quando:

o fluxo principal falhou;
nenhum documento válido permaneceu;
uma função obrigatória não foi carregada;
um destino DatasetOnly não foi validado;
pelo menos um documento do lote falhou.
Autenticação no PDM

Quando um arquivo de credenciais é configurado, ele é lido com Import-Clixml.

Crie o arquivo com:

PowerShell
Get-Credential |
Export-Clixml -Path "C:\Secure\vault-credential.xml"

A credencial normalmente fica vinculada ao usuário e ao computador onde foi criada.

A aplicação aceita:

um objeto PSCredential;
um objeto com Usuario e SenhaCriptografada.

Quando nenhuma credencial válida estiver disponível, a aplicação tenta utilizar LoginAuto.

Se a autenticação falhar, a pesquisa pode continuar utilizando somente o sistema de arquivos.

Validação de sintaxe do PowerShell

O projeto possui vários módulos PowerShell.

Use o script abaixo para validar o arquivo principal e todos os arquivos .ps1 da pasta functions sem executar a aplicação:

PowerShell
$files =
@(
Get-Item `
-LiteralPath ".\import_dcaPdfToTeamcenter.ps1" `
-ErrorAction Stop
 
Get-ChildItem `
-LiteralPath ".\functions" `
-Filter "*.ps1" `
-File `
-Recurse `
-ErrorAction Stop
)
 
foreach ($file in $files) {
 
$tokens =
$null
 
$errors =
$null
 
[System.Management.Automation.Language.Parser]::ParseFile(
$file.FullName,
[ref]$tokens,
[ref]$errors
) | Out-Null
 
if ($errors.Count -gt 0) {
 
Write-Host (
"Erros de sintaxe em: $($file.FullName)"
) -ForegroundColor Red
 
foreach ($syntaxError in $errors) {
 
Write-Host (
"Linha $($syntaxError.Extent.StartLineNumber): " +
$syntaxError.Message
) -ForegroundColor Red
}
 
exit 1
}
}
 
Write-Host (
"Sintaxe PowerShell valida. Arquivos verificados: $($files.Count)"
) -ForegroundColor Green

A validação de sintaxe não detecta problemas de execução, como:

nomes inválidos de objetos do Teamcenter;
variáveis de ambiente ausentes;
API do PDM indisponível;
caminhos inacessíveis;
métodos incompatíveis no assembly;
workflows inválidos;
falhas de consulta;
revisões existentes não encontradas;
permissões insuficientes;
falhas na criação da relação do Dataset.
Erros comuns
Função obrigatória não carregada

Exemplo:

Plain Text
A funcao obrigatoria 'Get-DcaTypeConfiguration' nao foi carregada.

Verifique:

o arquivo correspondente em $functionFiles;
o nome da função dentro do módulo;
possíveis erros de sintaxe;
arquivos ausentes;
caminhos incorretos;
commits incompletos.
Item já existe

O código já está registrado no Teamcenter.

Para os tipos normais, a aplicação não cria um código alternativo automaticamente.

Se a intenção é adicionar somente um PDF a uma revisão existente, o documento precisa utilizar o fluxo DatasetOnly.

Destino de Dataset não encontrado

Verifique:

código do Item;
revisão esperada;
ambiente conectado;
Saved Query;
propriedades da consulta;
permissões do usuário;
categoria do documento.
Revisão inválida

Verifique:

valor entre colchetes no nome;
variável de revisão configurada;
valor do cartão;
tipo do documento;
regras da configuração do Teamcenter.
PDF não disponível localmente

Verifique:

autenticação no PDM;
conexão com o Vault;
permissões do cache;
caminho do arquivo;
permissão de download;
utilização de -NoVaultApi.
Item criado, mas PDF não importado

Verifique:

caminho temporário;
tamanho do arquivo;
objeto de revisão;
nome do Dataset;
revisão do Dataset;
assinatura de ImportarPDF;
compatibilidade do assembly;
permissões de Dataset;
regras de relação no Teamcenter.
Workflow não solicitado

Verifique:

estado do PDM;
DCA_TC_APPROVED_WORKFLOW;
DCA_TC_OBSOLETE_WORKFLOW;
nome do template;
tipo da revisão;
permissões de workflow;
se o documento é DatasetOnly.
Status atual
Implementado
 Pesquisa pela API do SOLIDWORKS PDM.
 Pesquisa alternativa no sistema de arquivos.
 Pesquisa parcial automática.
 Curingas em pesquisas por código.
 Várias pesquisas separadas por vírgulas.
 Remoção de pesquisas repetidas.
 Seleção de vários PDFs.
 Pesquisa exata por pasta.
 Importação completa de pasta.
 Seleção individual dentro da pasta.
 Prevenção de documentos duplicados.
 Identificação da categoria.
 Interpretação do nome do PDF.
 Leitura da revisão no cartão.
 Leitura da descrição no cartão.
 Descoberta de variáveis do cartão.
 Criação de Desenho Original.
 Criação de Processo.
 Criação de Norma Externa.
 Localização de revisão existente.
 Fluxo DatasetOnly.
 Configuração dos tipos do Teamcenter.
 Mapeamento de propriedades da revisão.
 Consulta do estado do PDM.
 Solicitação de workflow de aprovação.
 Solicitação de workflow de obsolescência.
 Modo Preview.
 Modo detalhado.
 Apresentação do plano.
 Validação do PDF temporário.
 Tratamento individual de erros.
 Resumo final.
 Códigos de saída.
 Carregamento modular das funções.
 Validação das funções obrigatórias.
Pendente de validação ou melhoria
 Confirmar a importação do Dataset para todos os tipos de revisão.
 Confirmar a conclusão dos workflows no ambiente de Processo.
 Adicionar recuperação automática para Items criados sem PDF.
 Adicionar verificação posterior da relação do Dataset.
 Adicionar limpeza automática de PDFs temporários antigos.
 Ampliar os testes de interpretação de nomes e revisões.
 Adicionar geração opcional de arquivo de log.
Limitações
O projeto é específico para o modelo documental atual do DCA.
Os objetos e propriedades do Teamcenter variam entre ambientes.
A integração depende de um assembly compatível.
A integração com o PDM depende do cliente instalado.
As importações por pasta exigem categorias reconhecidas.
As pesquisas por pasta exigem o nome completo.
As pesquisas por pasta não aceitam curingas.
Processos e Desenhos Originais exigem revisões válidas.
Documentos DatasetOnly exigem Item e revisão existentes.
Arquivos com nomes não reconhecidos podem exigir correção manual.
Documentos inválidos podem ser ignorados durante importações por pasta.
Uma chamada sem exceção não confirma sozinha que a relação do Dataset foi criada.
A recuperação de Items criados sem PDF ainda não é automática.
Segurança
Nunca envie o arquivo .env ao repositório.
Nunca envie senhas ou tokens.
Nunca envie arquivos protegidos de credenciais.
Nunca publique URLs internas do Teamcenter.
Nunca publique nomes internos de objetos sem autorização.
Utilize contas com as permissões mínimas necessárias.
Revise os logs antes de compartilhá-los.
Armazene arquivos de credenciais em diretórios protegidos.
Mantenha assemblies internos fora do repositório quando necessário.
Aviso

Este repositório contém uma integração específica de ambiente.

Antes de utilizar o projeto em outra organização ou instalação:

substitua todos os valores de exemplo;
revise os requisitos de segurança;
valide os caminhos do PDM;
valide os campos dos cartões;
valide as configurações de conexão;
valide os objetos de negócio;
valide as regras de revisão;
valide os requisitos dos Datasets;
valide os templates de workflow;
valide o assembly de integração;
execute testes controlados fora do ambiente de produção.

Utilize o projeto somente em ambientes autorizados e com credenciais aprovadas.