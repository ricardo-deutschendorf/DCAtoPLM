# DCAtoPLM

> [!WARNING]
> Criação de Items e revisões, processamento em lote, pesquisa no PDM, pesquisa
> por pasta, importação de Dataset em revisão existente, preparação do PDF e
> solicitação de workflow já foram implementados. O comportamento da importação
> do PDF ainda depende do assembly de integração do Teamcenter instalado e deve
> ser validado em cada ambiente de destino antes do uso em produção.

Importa documentos PDF de um vault DCA local do SolidWorks PDM para o Siemens
Teamcenter.

O DCAtoPLM pesquisa o vault de documentação configurado, interpreta os metadados
do documento a partir do cartão de dados do PDM e do nome do PDF, cria o Item e a
revisão correspondentes (ou localiza uma revisão existente, no caso de
`DatasetOnly`), importa o PDF como Dataset e, quando aplicável, inicia um workflow
do Teamcenter conforme o estado atual no PDM.

A aplicação permite pesquisas individuais por código, várias pesquisas em uma
mesma execução, seleção múltipla de resultados e importação completa de pastas.

> [!IMPORTANT]
> A integração foi desenvolvida para o **Siemens Teamcenter 2312**.
>
> Outras versões do Teamcenter podem funcionar, mas a compatibilidade não foi
> confirmada. Objetos de negócio, propriedades, workflows e assemblies de
> integração do Teamcenter são específicos de cada ambiente e precisam ser
> revisados antes do uso.

---

## Principais funcionalidades

- Pesquisa de PDFs pela API do SolidWorks PDM.
- Pesquisa local alternativa quando a API do PDM não está disponível.
- Pesquisa parcial por código, sem necessidade de `*`.
- Curingas `*` e `?` nas pesquisas por código.
- Várias pesquisas separadas por vírgula, com remoção de termos repetidos.
- Seleção múltipla de resultados (número, lista, intervalo, `T` ou `TODOS`).
- Pesquisa de pasta por nome completo, com importação direta ou seleção dos
  documentos da pasta.
- Prevenção de arquivos duplicados no mesmo lote.
- Detecção da categoria do documento a partir do caminho de origem.
- Leitura dos cartões de dados do PDM (revisão e descrição).
- Extração de código, título e revisão a partir do nome do PDF.
- Criação de Items e revisões no Teamcenter.
- Importação de PDF como Dataset em revisão existente (`DatasetOnly`).
- Leitura do estado atual do workflow no PDM.
- Solicitação de workflows para documentos aprovados ou obsoletos.
- Plano de importação apresentado antes de qualquer alteração no Teamcenter.
- Continuação do lote quando um documento individual falha.
- Resumo final com os resultados do lote.
- Modo Preview, que não altera o Teamcenter.
- Modo Details, para diagnóstico.
- Carregamento modular com validação antecipada de arquivos e funções.

---

## Categorias de documentos suportadas

| Categoria de origem | Tipo interno | Finalidade |
| --- | --- | --- |
| `Desenhos Originais` | `Original` | Desenhos originais DCA |
| `FP - Ficha de Processo (PDF)` | `Processo` | Documentos de processo DCA |
| `Normas Externas` | `NormaExterna` | Normas externas DCA |
| `FP - XXRE Dimensional` | `DatasetOnly` | PDFs dimensionais importados em Items já existentes |

Cada categoria que cria Item é associada a um tipo de Item e a um tipo de
revisão do Teamcenter por variáveis de ambiente. Os mapeamentos podem ser
diferentes nos ambientes de teste e de processo.

### Categoria `FP - XXRE Dimensional` (`DatasetOnly`)

Esta categoria usa um fluxo diferente das demais. O fluxo `DatasetOnly`:

- **não** cria um novo Item;
- **não** cria uma nova revisão;
- procura um Item e uma revisão existentes;
- importa somente o PDF como Dataset;
- **não** solicita workflow.

O destino (Item e revisão) é validado antes da confirmação do lote. Veja a seção
[Fluxos do Teamcenter](#fluxos-do-teamcenter).

---

## Estados de workflow suportados

O DCAtoPLM lê o estado atual de cada arquivo no SolidWorks PDM. Os estados abaixo
podem disparar workflows do Teamcenter:

| Estado no PDM | Ação no Teamcenter |
| --- | --- |
| `Aprovado` | Inicia o workflow configurado em `DCA_TC_APPROVED_WORKFLOW` |
| `Obsoleto` | Inicia o workflow configurado em `DCA_TC_OBSOLETE_WORKFLOW` |
| Qualquer outro estado | Importa o Item e o PDF sem iniciar workflow |

O workflow só é solicitado depois que as etapas de criação do Item e importação do
PDF terminam sem exceção. Documentos `DatasetOnly` nunca solicitam workflow.

> [!NOTE]
> Chamar o assembly de integração sem exceção confirma apenas que o método de
> workflow foi solicitado. O comportamento final depende do template e dos
> handlers configurados no Teamcenter.

---

## Estrutura do repositório

```text
DCAtoPLM/
├── import_dcaPdfToTeamcenter.ps1
├── functions/
│   ├── output_functions.ps1
│   ├── pdm_modules/
│   ├── import_plan_modules/
│   ├── search_modules/
│   └── teamcenter_modules/
├── start_DCAtoPLM.bat
├── .env.example
├── .env
└── README.md
```

| Arquivo ou pasta | Responsabilidade |
| --- | --- |
| `import_dcaPdfToTeamcenter.ps1` | Script principal: carregamento e validação dos módulos, parâmetros, prompts, orquestração do lote e códigos de saída |
| `functions/output_functions.ps1` | Funções de saída no console, incluindo mensagens, destaques e atraso entre linhas |
| `functions/pdm_modules` | Acesso ao SolidWorks PDM: autenticação, download de arquivos, estado do workflow e leitura dos cartões de dados |
| `functions/import_plan_modules` | Interpretação dos documentos, preparação do lote e montagem do plano de importação |
| `functions/search_modules` | Pesquisa por código e por pasta, seleção de resultados e remoção de duplicidades |
| `functions/teamcenter_modules` | Conexão com o Teamcenter, criação de Items, localização de revisões, importação de Datasets e solicitação de workflows |
| `start_DCAtoPLM.bat` | Inicializador recomendado para Windows |
| `.env.example` | Modelo seguro de configuração |
| `.env` | Configuração local do ambiente, nunca enviada ao repositório |

> [!NOTE]
> O arquivo antigo `functions/teamcenter_functions.ps1` não existe mais. Suas
> responsabilidades foram distribuídas entre os módulos acima.

---

## Requisitos

O ambiente de execução precisa ter:

- Windows PowerShell compatível com os scripts.
- Acesso ao Siemens Teamcenter 2312.
- Conta do Teamcenter com permissão para criar Items e revisões.
- Permissão para importar Datasets PDF.
- Permissão para iniciar os workflows configurados.
- Acesso ao cliente SolidWorks PDM.
- `Interop.EdmLib.dll`.
- Acesso ao vault SolidWorks PDM configurado.
- Assembly de integração do Teamcenter compatível, como `Importar GD.exe`.
- Acesso ao cache local do PDM ou permissão para baixar arquivos para ele.

Normalmente não são necessários privilégios de administrador.

---

## Estrutura esperada do vault

A raiz configurada é informada por `DCA_ROOT` ou `-SearchRoot`.

Exemplo:

```text
C:\VAULT_ROOT
```

O script localiza o diretório de documentação abaixo dessa raiz:

```text
C:\VAULT_ROOT\
└── Documentação\
    ├── Desenhos Originais\
    │   ├── CLIENTE_A\
    │   └── CLIENTE_B\
    │
    ├── FP - Ficha de Processo (PDF)\
    │   ├── CLIENTE_A\
    │   ├── CLIENTE_B\
    │   └── instruções\
    │
    ├── FP - XXRE Dimensional\
    │
    └── Normas Externas\
        ├── AMS\
        ├── ASTM\
        ├── MIL\
        └── outras normas\
```

As pesquisas de pasta percorrem toda a árvore de documentação, mas somente
arquivos dentro de uma categoria reconhecida podem ser convertidos em objetos do
Teamcenter.

A categoria determina o tipo de documento:

```text
Desenhos Originais            -> Original
FP - Ficha de Processo (PDF)  -> Processo
Normas Externas               -> NormaExterna
FP - XXRE Dimensional         -> DatasetOnly
```

---

## Configuração do ambiente

O método recomendado é um arquivo `.env` local.

Copie:

```text
.env.example
```

para:

```text
.env
```

Em seguida, substitua todos os valores de exemplo pelos valores adequados à
estação de trabalho e ao ambiente de destino.

> [!CAUTION]
> O arquivo `.env` **não deve ser enviado ao repositório**. Ele pode conter
> credenciais, caminhos internos e endereços de servidores.

URLs, usuários, senhas, caminhos e nomes de objetos de negócio são específicos de
cada ambiente. Os valores abaixo são apenas ilustrativos.

### Exemplo de configuração

```ini
# ============================================================
# Vault DCA e PDM
# ============================================================

DCA_ROOT=C:\VAULT_ROOT
DCA_VAULT_NAME=NOME_DO_VAULT
DCA_PDM_LIB=C:\Caminho\Para\Interop.EdmLib.dll
DCA_VAULT_CREDENTIAL=C:\Secure\vault-credential.xml
DCA_TEMP_FOLDER=C:\Temp\DCAtoPLM

# ============================================================
# Cartões de dados do PDM
# Nomes das variáveis do cartão que contêm revisão e descrição.
# Várias variáveis de revisão podem ser separadas por | ou ;
# ============================================================

DCA_PDM_VAR_ORIGINAL_REVISION=<VARIAVEL_REVISAO_ORIGINAL>
DCA_PDM_VAR_PROCESS_REVISION=<VARIAVEL_REVISAO_PROCESSO>
DCA_PDM_VAR_STANDARD_REVISION=<VARIAVEL_REVISAO_NORMA>
DCA_PDM_VAR_DATASET_REVISION=<VARIAVEL_REVISAO_DATASET>

DCA_PDM_VAR_ORIGINAL_DESCRIPTION=<VARIAVEL_DESCRICAO_ORIGINAL>
DCA_PDM_VAR_PROCESS_DESCRIPTION=<VARIAVEL_DESCRICAO_PROCESSO>
DCA_PDM_VAR_STANDARD_DESCRIPTION=<VARIAVEL_DESCRICAO_NORMA>

DCA_PDM_DISCOVER_CARD_VARIABLES=<VALOR>

# ============================================================
# Assembly de integração do Teamcenter
# ============================================================

DCA_IMPORTER_PATH=C:\Caminho\Para\Importar GD.exe

# ============================================================
# Ambiente do Teamcenter selecionado
# Valores válidos: Teste ou Processo
# ============================================================

DCA_TC_ENV=Teste

# ============================================================
# Teamcenter - ambiente de teste
# ============================================================

DCA_TC_TEST_URL=<URL_TEAMCENTER_TESTE>
DCA_TC_TEST_USER=<USUARIO_TEAMCENTER_TESTE>
DCA_TC_TEST_PASSWORD=<SENHA_TEAMCENTER_TESTE>

# ============================================================
# Teamcenter - ambiente de processo (produção)
# ============================================================

DCA_TC_PROCESS_URL=<URL_TEAMCENTER_PROCESSO>
DCA_TC_PROCESS_USER=<USUARIO_TEAMCENTER_PROCESSO>
DCA_TC_PROCESS_PASSWORD=<SENHA_TEAMCENTER_PROCESSO>

# ============================================================
# Templates de workflow do Teamcenter
# ============================================================

DCA_TC_APPROVED_WORKFLOW=<TEMPLATE_WORKFLOW_APROVADO>
DCA_TC_OBSOLETE_WORKFLOW=<TEMPLATE_WORKFLOW_OBSOLETO>

# ============================================================
# Objetos de negócio - ambiente de teste
# ============================================================

DCA_TC_TEST_ORIGINAL_ITEM_TYPE=<TIPO_ITEM_ORIGINAL>
DCA_TC_TEST_ORIGINAL_REVISION_TYPE=<TIPO_REVISAO_ORIGINAL>
DCA_TC_TEST_ORIGINAL_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_TEST_ORIGINAL_CLIENT_VALUE=<VALOR_CLIENTE>

DCA_TC_TEST_PROCESS_ITEM_TYPE=<TIPO_ITEM_PROCESSO>
DCA_TC_TEST_PROCESS_REVISION_TYPE=<TIPO_REVISAO_PROCESSO>
DCA_TC_TEST_PROCESS_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_TEST_PROCESS_CLIENT_VALUE=<VALOR_CLIENTE>

DCA_TC_TEST_STANDARD_ITEM_TYPE=<TIPO_ITEM_NORMA>
DCA_TC_TEST_STANDARD_REVISION_TYPE=<TIPO_REVISAO_NORMA>
DCA_TC_TEST_STANDARD_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_TEST_STANDARD_CLIENT_VALUE=<VALOR_CLIENTE>

# ============================================================
# Objetos de negócio - ambiente de processo (produção)
# ============================================================

DCA_TC_PROCESS_ORIGINAL_ITEM_TYPE=<TIPO_ITEM_ORIGINAL>
DCA_TC_PROCESS_ORIGINAL_REVISION_TYPE=<TIPO_REVISAO_ORIGINAL>
DCA_TC_PROCESS_ORIGINAL_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_PROCESS_ORIGINAL_CLIENT_VALUE=<VALOR_CLIENTE>

DCA_TC_PROCESS_PROCESS_ITEM_TYPE=<TIPO_ITEM_PROCESSO>
DCA_TC_PROCESS_PROCESS_REVISION_TYPE=<TIPO_REVISAO_PROCESSO>
DCA_TC_PROCESS_PROCESS_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_PROCESS_PROCESS_CLIENT_VALUE=<VALOR_CLIENTE>

DCA_TC_PROCESS_STANDARD_ITEM_TYPE=<TIPO_ITEM_NORMA>
DCA_TC_PROCESS_STANDARD_REVISION_TYPE=<TIPO_REVISAO_NORMA>
DCA_TC_PROCESS_STANDARD_CLIENT_PROPERTY=<PROPRIEDADE_CLIENTE>
DCA_TC_PROCESS_STANDARD_CLIENT_VALUE=<VALOR_CLIENTE>
```

### Alterações necessárias antes do uso

Antes de usar o projeto em outra empresa, vault, estação ou ambiente Teamcenter,
revise:

| Configuração | Onde configurar |
| --- | --- |
| Raiz local do vault | `DCA_ROOT` ou `-SearchRoot` |
| Nome do vault SolidWorks PDM | `DCA_VAULT_NAME` ou `-VaultName` |
| Biblioteca de interoperabilidade do PDM | `DCA_PDM_LIB` ou `-PdmLibraryPath` |
| Arquivo de credencial protegido do PDM | `DCA_VAULT_CREDENTIAL` ou `-VaultCredentialPath` |
| Diretório temporário dos PDFs | `DCA_TEMP_FOLDER` |
| Variáveis dos cartões de dados do PDM | `DCA_PDM_VAR_*` e `DCA_PDM_DISCOVER_CARD_VARIABLES` |
| Assembly de integração do Teamcenter | `DCA_IMPORTER_PATH` |
| Ambiente do Teamcenter | `DCA_TC_ENV` |
| Conexão do Teamcenter de teste | Variáveis `DCA_TC_TEST_*` |
| Conexão do Teamcenter de processo | Variáveis `DCA_TC_PROCESS_*` |
| Objetos de negócio | Variáveis de Item e revisão de cada ambiente |
| Workflow de aprovação | `DCA_TC_APPROVED_WORKFLOW` |
| Workflow de obsolescência | `DCA_TC_OBSOLETE_WORKFLOW` |

O código-fonte evita armazenar credenciais de produção ou configurações internas
da empresa.

---

## Executando a aplicação

### Inicializador recomendado

```text
start_DCAtoPLM.bat
```

O inicializador executa o fluxo PowerShell usando a configuração local.

### Execução direta pelo PowerShell

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\import_dcaPdfToTeamcenter.ps1
```

### Modo Preview

```powershell
.\import_dcaPdfToTeamcenter.ps1 `
  -SourceCode "AMS 22" `
  -Preview
```

O modo Preview realiza pesquisa, seleção, extração de metadados e apresentação do
plano e do resumo do lote, mas **não**:

- conecta ao Teamcenter;
- cria Items;
- cria revisões;
- copia arquivos para o diretório de importação;
- importa PDFs;
- inicia workflows.

### Modo Details

```powershell
.\import_dcaPdfToTeamcenter.ps1 `
  -SourceCode "AMS 22" `
  -Preview `
  -Details `
  -OutputDelayMilliseconds 0
```

`-Details` exibe informações adicionais de caminhos, de cada documento e de
diagnóstico. No plano de importação, também apresenta servidor, caminhos,
propriedades e templates.

---

## Parâmetros

| Parâmetro | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `-SearchRoot` | string | `DCA_ROOT` | Raiz do vault DCA configurado |
| `-SourceCode` | string | Vazio | Códigos, padrões ou pesquisas de pasta separados por vírgula |
| `-ItemName` | string | Vazio | Nome inicial opcional do Item no Teamcenter |
| `-VaultName` | string | `DCA_VAULT_NAME` | Nome do vault SolidWorks PDM |
| `-PdmLibraryPath` | string | `DCA_PDM_LIB` | Caminho do `Interop.EdmLib.dll` |
| `-VaultCredentialPath` | string | `DCA_VAULT_CREDENTIAL` | Arquivo de credencial protegido |
| `-OutputDelayMilliseconds` | int | `10` | Atraso entre linhas de saída |
| `-NoVaultApi` | switch | Desativado | Pesquisa somente arquivos disponíveis localmente |
| `-Details` | switch | Desativado | Exibe informações detalhadas de pesquisa e diagnóstico |
| `-Preview` | switch | Desativado | Prepara o lote sem alterar o Teamcenter |

---

## Comportamento da pesquisa

### Pesquisa por código

A pesquisa por código é **parcial por padrão**. Ao digitar:

```text
AMS 22
```

podem ser retornados:

```text
AMS 2241
AMS 2242
AMS 2248
AMS 2261
AMS 2262
```

Não é necessário incluir `*` em pesquisas parciais comuns.

Os curingas continuam suportados, **somente em pesquisas por código**:

```text
AMS 22*
*2248*
BR50??A-00
```

| Curinga | Significado |
| --- | --- |
| `*` | Zero ou mais caracteres |
| `?` | Exatamente um caractere |

#### Várias pesquisas

Separe as pesquisas por vírgula:

```text
1000359,1000359-2,AMS 2248
```

Cada valor é pesquisado de forma independente. Termos repetidos são removidos
antes da pesquisa.

#### Seleção de resultados

Quando a pesquisa retorna mais de um PDF, a seleção aceita:

| Entrada | Efeito |
| --- | --- |
| `2` | Seleciona um resultado individual |
| `1,2,4` | Seleciona vários números separados por vírgula |
| `1-3` | Seleciona um intervalo |
| `T` | Seleciona todos os resultados exibidos |
| `TODOS` | Seleciona todos os resultados exibidos |

Quando a pesquisa retorna um único resultado, ele é selecionado
automaticamente. Cada PDF selecionado vira uma entrada independente do lote.

### Pesquisa por pasta

A pesquisa por pasta exige o **nome completo** da pasta. Ela é feita em toda a
árvore de documentação e possui dois modos:

| Entrada | Modo | Comportamento |
| --- | --- | --- |
| `\NomeCompleto` | Importação direta | Importa os documentos válidos da pasta |
| `\\NomeCompleto` | Seleção | Abre a seleção dos documentos da pasta |

As barras normais também são aceitas: `/NomeCompleto` equivale a
`\NomeCompleto`, e `//NomeCompleto` equivale a `\\NomeCompleto`.

Exemplos:

```text
\MIL
\\MIL
/MIL
//MIL
```

> [!IMPORTANT]
> Pesquisas por pasta **não** aceitam curingas nem pesquisas parciais. Os
> caracteres `*`, `?`, a sequência `..` e caracteres inválidos em nomes de pasta
> são bloqueados.

Somente os PDFs diretamente contidos na pasta são considerados. Arquivos duplicados
no mesmo lote são evitados.

---

## Cartões de dados do PDM

O DCAtoPLM lê variáveis dos cartões de dados do SolidWorks PDM para obter revisão
e descrição. Os nomes das variáveis são configurados no `.env`.

### Variáveis de revisão

| Variável | Uso |
| --- | --- |
| `DCA_PDM_VAR_ORIGINAL_REVISION` | Revisão de Desenhos Originais |
| `DCA_PDM_VAR_PROCESS_REVISION` | Revisão de documentos de Processo |
| `DCA_PDM_VAR_STANDARD_REVISION` | Revisão de Normas Externas |
| `DCA_PDM_VAR_DATASET_REVISION` | Revisão de destino para `DatasetOnly` |

### Variáveis de descrição

| Variável | Uso |
| --- | --- |
| `DCA_PDM_VAR_ORIGINAL_DESCRIPTION` | Descrição de Desenhos Originais |
| `DCA_PDM_VAR_PROCESS_DESCRIPTION` | Descrição de documentos de Processo |
| `DCA_PDM_VAR_STANDARD_DESCRIPTION` | Descrição de Normas Externas |

### Descoberta de variáveis

`DCA_PDM_DISCOVER_CARD_VARIABLES` controla a descoberta das variáveis disponíveis
no cartão, útil para identificar os nomes corretos ao configurar um novo vault.

### Regras de leitura

- Várias variáveis de revisão podem ser informadas em uma mesma configuração,
  separadas por `|` ou `;`.
- Os valores encontrados no cartão têm **prioridade** sobre os valores extraídos
  do nome do PDF.
- A descrição de **Desenhos Originais** passa por uma normalização antes de ser
  usada.

---

## Plano de importação

Antes de qualquer alteração no Teamcenter, o plano de importação é apresentado
para conferência. Ele informa:

- ambiente;
- quantidade de documentos;
- tipos do Item e da revisão;
- propriedades adicionais;
- revisão prevista;
- estado do PDM;
- workflow previsto;
- erros de configuração.

No modo `-Details`, o plano também apresenta servidor, caminhos, propriedades e
templates.

---

## Processamento do lote

Cada documento preparado é processado de forma independente. O fluxo depende do
tipo do documento.

### Resultados individuais

| Resultado | Significado |
| --- | --- |
| Item e PDF importados | Item criado e PDF importado como Dataset; workflow solicitado quando aplicável |
| Item criado, mas PDF não importado | O Item existe no Teamcenter sem o PDF e exige revisão manual |
| Item não criado | O Item não foi criado e o PDF não foi processado |
| Dataset importado em revisão existente | Fluxo `DatasetOnly` concluído |
| Dataset não importado em revisão existente | Fluxo `DatasetOnly` falhou |

Uma falha individual **não interrompe** os próximos documentos do lote.

Falhas anteriores ao processamento do lote (por exemplo, arquivo ou função
ausente, ou falha na conexão) podem interromper toda a execução.

O resumo final apresenta o total de entradas concluídas e com falha.

---

## Fluxos do Teamcenter

### Criação de Item

Aplicável a:

- `Original`
- `Processo`
- `NormaExterna`

Etapas principais:

1. Criar o Item.
2. Obter ou localizar a revisão.
3. Preparar o PDF.
4. Importar o Dataset.
5. Solicitar workflow, quando aplicável.
6. Registrar o resultado.

### Dataset em revisão existente

Aplicável a:

- `DatasetOnly`

Etapas principais:

1. Procurar o Item existente.
2. Procurar a revisão esperada.
3. Validar o destino antes da confirmação.
4. Preparar o PDF.
5. Importar somente o Dataset.

Neste fluxo, o DCAtoPLM **não** cria Item, **não** cria revisão e **não**
solicita workflow. Se o destino não for validado, o documento falha e o código de
saída reflete essa falha.

---

## Ambiente de Processo

Quando o ambiente selecionado é `Processo`, a aplicação apresenta um aviso
destacado.

Existe uma **confirmação geral** do lote, feita digitando `SIM`. Não existe uma
segunda confirmação exclusiva para o ambiente de Processo.

---

## Preparação do PDF

O PDF original **nunca é alterado**. A importação usa uma cópia temporária criada
em `DCA_TEMP_FOLDER`.

Antes de chamar o método de importação do Teamcenter, o script:

1. Confirma que o PDF está disponível no cache local do PDM, baixando-o quando
   necessário.
2. Substitui caracteres inválidos do código antes de criar o nome temporário.
3. Copia o PDF para `DCA_TEMP_FOLDER`.
4. Valida a cópia temporária quanto a:
   - existência;
   - extensão;
   - tamanho;
   - comparação com o arquivo original;
   - acesso de leitura.
5. Passa o caminho do PDF e a revisão do Teamcenter ao assembly de integração.

A integração espera atualmente um método compatível com:

```text
ImportarPDF(
    DatasetId,
    DatasetRev,
    pathArquivo,
    ItemRevision,
    Sobrepor
)
```

O comportamento exato depende do assembly `Importar GD.exe` instalado.

> [!CAUTION]
> Os requisitos de `DatasetId` e `DatasetRev` devem ser confirmados no assembly de
> integração usado pelo ambiente Teamcenter de destino. Um valor incompatível
> pode fazer o Item ser criado sem que o PDF seja anexado.

---

## Workflows do Teamcenter

Após a importação bem-sucedida do PDF, o DCAtoPLM pode chamar:

```text
Start_Workflow(
    Workflow_Template,
    Revisions
)
```

O workflow escolhido depende do estado no PDM:

```text
Aprovado -> DCA_TC_APPROVED_WORKFLOW
Obsoleto -> DCA_TC_OBSOLETE_WORKFLOW
```

Documentos em estados como:

```text
Verificado
Em verificação
```

são importados sem workflow automático, a menos que uma regra adicional seja
implementada.

O template precisa existir no Teamcenter e suportar o tipo de revisão submetida.

---

## Regras específicas por tipo de documento

### Desenho Original DCA

Categoria de origem:

```text
Desenhos Originais
```

Exemplos de revisão:

```text
B
BA
```

A configuração atual valida o tamanho da revisão do Teamcenter. Se o modelo do
Teamcenter de destino aceitar revisões maiores, ajuste a validação em
`Get-DcaTypeConfiguration`.

### Processo DCA

Categoria de origem:

```text
FP - Ficha de Processo (PDF)
```

Formato esperado da revisão:

```text
A4
BA4
AA4
--4
```

O último caractere representa a revisão interna. Por exemplo, `BA4` é interpretado
como:

```text
Revisão completa: BA4
Revisão cliente:  BA
Revisão interna:  4
```

Texto entre colchetes só é aceito como revisão quando corresponde ao formato
válido. Por exemplo, `1000359-2[BA4].pdf` é válido, enquanto
`1000359-2[TESTE].pdf` não é aceito automaticamente como revisão.

### Norma Externa DCA

Categoria de origem:

```text
Normas Externas
```

Normas externas usam a revisão:

```text
000
```

O analisador reconhece vários formatos de código técnico, incluindo:

```text
AMS 2248
AMS 2759-3
AMS 2440C
AMS-STD-2175
MIL-PRF-85582
ASTM-A123
```

Quando possível, o texto após o código é interpretado como título. Por exemplo,
`AMS 2248 CHEMICAL CHECK ANALYSIS LIMITS.pdf` resulta em:

```text
Código: AMS 2248
Nome:   CHEMICAL CHECK ANALYSIS LIMITS
```

### Dimensional (`DatasetOnly`)

Categoria de origem:

```text
FP - XXRE Dimensional
```

Importa somente o PDF como Dataset em um Item e uma revisão **já existentes**. A
revisão esperada pode ser obtida da variável `DCA_PDM_VAR_DATASET_REVISION`.

---

## Itens duplicados

Nos fluxos de criação de Item, se o Item já existir no Teamcenter, o script
informa a duplicidade. A aplicação **não** gera um código alternativo
automaticamente.

```text
O item 'AMS 2248' já existe no Teamcenter.
```

No processamento em lote, a duplicidade é registrada como falha individual e a
aplicação continua com o próximo documento.

---

## Arquivos temporários

Os arquivos temporários de importação são armazenados em `DCA_TEMP_FOLDER`.
Exemplo:

```text
C:\Temp\DCAtoPLM
```

O nome do PDF temporário é baseado no código do Item do Teamcenter. Caracteres
inválidos em nomes de arquivo do Windows são substituídos antes da criação do
caminho temporário.

Os arquivos temporários ainda **não** são removidos automaticamente.

---

## Autenticação no PDM

Quando um arquivo de credencial é configurado, o script o lê com
`Import-Clixml`. Para criar um arquivo de credencial protegido:

```powershell
Get-Credential |
  Export-Clixml -Path "C:\Secure\vault-credential.xml"
```

A credencial criptografada normalmente fica vinculada ao usuário e ao computador
Windows que a criou.

Sem arquivo de credencial, a aplicação tenta `LoginAuto`, que exige uma sessão
ativa do SolidWorks PDM para o usuário atual do Windows.

---

## Ambientes do Teamcenter

Dois ambientes são suportados:

```text
Teste
Processo
```

Selecione o ambiente em:

```ini
DCA_TC_ENV=Teste
```

ou:

```ini
DCA_TC_ENV=Processo
```

Veja [Ambiente de Processo](#ambiente-de-processo) para o comportamento de
confirmação.

---

## Procedimento recomendado para produção

Antes de executar uma importação em produção:

1. Atualize o `.env` com a configuração aprovada.
2. Confirme o ambiente Teamcenter selecionado.
3. Confirme que a conta do PDM consegue ler e baixar os PDFs selecionados.
4. Confirme que a conta do Teamcenter consegue criar os tipos de Item necessários.
5. Confirme que a conta do Teamcenter consegue criar relações de Dataset.
6. Confirme que os templates de workflow existem.
7. Execute a mesma pesquisa com `-Preview`.
8. Revise tipos de documento, revisões, estados e códigos extraídos no plano.
9. Comece com um único documento de teste controlado.
10. Inspecione o Item, a revisão, o Dataset do PDF e o workflow criados.
11. Execute lotes maiores somente depois que o teste controlado for bem-sucedido.

---

## Segurança

- Nunca envie o `.env` ao repositório.
- Nunca envie senhas ou tokens de acesso.
- Nunca envie arquivos de credencial protegidos.
- Nunca publique URLs internas do Teamcenter.
- Nunca publique nomes internos de objetos de negócio sem autorização.
- Mantenha os assemblies de integração do Teamcenter fora do repositório.
- Use contas com o mínimo de permissões necessárias.
- Revise logs antes de compartilhá-los, pois podem conter caminhos internos,
  códigos de Items, nomes de servidores e usuários.

---

## Carregamento e validação de módulos

Os módulos em `functions` são carregados por *dot source*. Antes da execução:

1. Cada arquivo é validado antes de ser carregado.
2. As funções obrigatórias são verificadas **antes da pesquisa**.
3. Um arquivo ou função ausente interrompe a execução antes de qualquer alteração
   externa.

---

## Códigos de saída

| Código | Situação |
| --- | --- |
| `0` | Lote concluído com sucesso |
| `0` | Preview concluído |
| `0` | Operação cancelada antes das alterações |
| `1` | Falha no fluxo principal |
| `1` | Função obrigatória ausente |
| `1` | Documento com falha |
| `1` | Destino `DatasetOnly` não validado |

---

## Validação de sintaxe do PowerShell

Valide o script principal e todos os arquivos `.ps1` de `functions`,
recursivamente, sem executar a aplicação:

```powershell
$files = @(
  Get-Item ".\import_dcaPdfToTeamcenter.ps1"
  Get-ChildItem ".\functions" -Recurse -Filter "*.ps1"
)

foreach ($file in $files) {

  $tokens = $null
  $errors = $null

  [System.Management.Automation.Language.Parser]::ParseFile(
    $file.FullName,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null

  if ($errors.Count -gt 0) {

    Write-Host "Erros de sintaxe em: $($file.FullName)" -ForegroundColor Red

    $errors | ForEach-Object {
      Write-Host (
        "Linha $($_.Extent.StartLineNumber): " + $_.Message
      ) -ForegroundColor Red
    }

    exit 1
  }
}

Write-Host "Sintaxe do PowerShell OK" -ForegroundColor Green
```

A validação de sintaxe **não** detecta problemas de execução, como:

- nomes inválidos de objetos de negócio do Teamcenter;
- variáveis de ambiente ausentes;
- APIs do PDM indisponíveis;
- métodos incompatíveis no assembly de integração;
- templates de workflow inválidos;
- convenções inválidas de nome de PDF;
- erros de reflexão dentro do executável de integração do Teamcenter.

---

## Erros comuns

### Item já existe

```text
O item já existe no Teamcenter.
```

O código já está registrado. A aplicação não cria outro código automaticamente.

### Formato de revisão inválido

```text
A revisão não segue o padrão do Processo DCA.
```

Verifique o texto entre colchetes no nome do PDF e o valor do cartão de dados do
PDM.

### PDF não disponível localmente

```text
PDF não encontrado no disco.
```

Confirme a autenticação no PDM e o acesso ao cache local.

### Item criado, mas PDF não importado

```text
Item criado, mas PDF não importado.
```

Revise:

- a assinatura do método `ImportarPDF`;
- `DatasetId`;
- `DatasetRev`;
- o caminho do PDF temporário;
- a revisão retornada pelo Teamcenter;
- a compatibilidade do assembly de integração;
- as permissões de criação de Dataset.

### Destino `DatasetOnly` não encontrado

O Item ou a revisão esperada não existe no Teamcenter. Confirme o código do Item,
a revisão informada no cartão (`DCA_PDM_VAR_DATASET_REVISION`) e o ambiente
selecionado.

### Workflow não iniciado

Verifique:

- o estado no PDM;
- `DCA_TC_APPROVED_WORKFLOW`;
- `DCA_TC_OBSOLETE_WORKFLOW`;
- o nome do template de workflow;
- a compatibilidade com o tipo de revisão submetida;
- as permissões de workflow no Teamcenter.

---

## Status atual

### Implementado

- [x] Pesquisa pela API do PDM.
- [x] Pesquisa local alternativa.
- [x] Pesquisa parcial por código.
- [x] Seleção múltipla.
- [x] Pesquisa exata por pasta.
- [x] Importação completa de pasta.
- [x] Leitura dos cartões do PDM.
- [x] Criação de Items.
- [x] Importação `DatasetOnly`.
- [x] Workflows.
- [x] Preview.
- [x] Modo Details.
- [x] Preparação do PDF.
- [x] Plano de importação.
- [x] Tratamento individual de erros.
- [x] Resumo final.
- [x] Carregamento modular.
- [x] Validação das funções.

### Pendente de validação ou melhoria

- [ ] Confirmar a criação da relação do Dataset em todos os tipos.
- [ ] Confirmar a conclusão dos workflows no ambiente de Processo.
- [ ] Adicionar recuperação de Items criados sem PDF.
- [ ] Adicionar verificação posterior da relação do Dataset.
- [ ] Adicionar limpeza automática dos arquivos temporários.
- [ ] Ampliar os testes de interpretação dos nomes e revisões.
- [ ] Adicionar geração opcional de logs.

---

## Limitações

- O projeto é específico do modelo de documentos DCA atual.
- Nomes de objetos e propriedades do Teamcenter são específicos de cada ambiente.
- A integração depende de um `Importar GD.exe` compatível.
- A integração com o PDM depende do cliente SolidWorks PDM instalado.
- Importações de pasta exigem categorias de documento reconhecíveis.
- Documentos Original e Processo exigem revisões válidas.
- Arquivos com convenções de nome não suportadas podem exigir correção manual ou
  ser ignorados em importações de pasta.
- Uma chamada de reflexão bem-sucedida não prova, por si só, que o Dataset ou o
  workflow foram concluídos, a menos que haja verificação explícita.
- A recuperação de Items criados sem PDF ainda não é automatizada.

---

## Aviso

Este repositório contém um exemplo de integração específico de ambiente. Antes de
usar o projeto em outra organização:

- substitua todos os valores de exemplo;
- revise os requisitos de segurança;
- valide o mapeamento dos objetos de negócio;
- valide os templates de workflow;
- valide o assembly de integração;
- execute testes controlados em um ambiente que não seja de produção.

Use o projeto somente em ambientes autorizados e com credenciais aprovadas.