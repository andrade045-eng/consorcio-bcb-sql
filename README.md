# Índice de Exclusão no Sistema de Consórcios

Análise em SQL do sistema de consórcios brasileiro a partir dos dados
públicos do Banco Central. Foco no **índice de exclusão** — a proporção
de cotas que saem do grupo antes do fim — comparado entre segmentos de
bem e entre modelos de administradora.

## Por que

O consórcio movimenta volume relevante do crédito brasileiro e tem pouca
análise pública. O BCB publicava anualmente o *Panorama do Sistema de
Consórcios*; a publicação foi descontinuada e substituída pela
divulgação direta das bases no Portal de Dados Abertos. Quem quiser a
leitura consolidada agora precisa construí-la.

## Fontes

| Fonte | Uso |
|---|---|
| BCB — Banco de dados de consórcios (`bcb.gov.br/fis/consorcios`) | Base principal: "Dados Consolidados" > "Segmentos Consolidados" |
| BCB — "Significado dos campos & Métricas" | Dicionário de dados e fórmula oficial de cada campo |
| BCB — Panorama do Sistema de Consórcios (2019–2024, PDF) | Validação dos números calculados aqui |

Layout confirmado na data-base 202606: 19 colunas, separador `;`,
encoding WIN1252, decimal com vírgula.

## Ambiente

```bash
docker compose up -d                                    # sobe o Postgres
docker compose exec postgres psql -U danilo -d consorcio # entra no banco
```

O banco roda na porta **5433** do host (5432 costuma estar ocupada). A
pasta do projeto aparece dentro do container como `/projeto`.

Dentro do psql: `\i` executa arquivo, `\dt consorcio.*` lista tabelas,
`\x auto` melhora a leitura de saídas largas, `\q` sai.

## Execução

```
\i /projeto/01_schema.sql        -- cria schema, dimensões e fato
```

Importe o CSV (baixado do BCB e salvo como CSV em `dados/`):

```
\copy consorcio.stg_segmentos FROM '/projeto/dados/segmentos.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'WIN1252')
```

```
\i /projeto/02_carga.sql         -- limpeza, carga e testes
\i /projeto/03_classificacao.sql -- classifica as administradoras
\i /projeto/04_analise.sql       -- consultas de análise
```

O `01_schema.sql` apaga e recria as tabelas — não rode de novo sobre
dados já carregados.

## Modelo

```
stg_segmentos          espelho do arquivo, tudo text
dim_segmento           os 6 segmentos de bem do BCB
dim_administradora     126 administradoras + classificação do autor
fato_segmento_mensal   data_base × administradora × segmento
```

`cotas_ativas` é coluna calculada: o arquivo não a traz, e ela é a soma
de contempladas e não contempladas.

## Testes de carga

Rodados a cada importação, na seção 6 do `02_carga.sql`:

1. Contagem staging × fato
2. Falha de conversão numérica
3. **Consistência interna**: o arquivo reparte as cotas ativas de duas
   formas (por contemplação e por adimplência) e as somas têm que
   coincidir
4. Panorama por data-base

### Resultado — 7 data-bases (dez/2024 e jan–jun/2026)

| Teste | Resultado |
|---|---|
| Linhas staging → fato | 5.442 → 5.442 |
| Conversões nulas | 0 |
| Consistência interna (202606) | 3 divergências em 756 registros |
| Administradoras | 126 a 131, conforme a data-base |

As divergências de consistência (Breitkopf, Conshop e Fiel em jun/2026)
têm desvio máximo de 3 cotas e vêm do arquivo de origem, não da carga.

### Série carregada

| Data-base | Administradoras | Cotas ativas | Cotas excluídas |
|---|---|---|---|
| dez/2024 | 129 | 11.351.351 | 10.746.147 |
| jan/2026 | 131 | 12.846.432 | 12.175.944 |
| fev/2026 | 131 | 12.889.448 | 12.260.857 |
| mar/2026 | 131 | 13.002.574 | 12.409.137 |
| abr/2026 | 130 | 13.162.523 | 12.325.295 |
| mai/2026 | 129 | 13.252.424 | 12.647.809 |
| jun/2026 | 126 | 13.158.595 | 12.550.895 |

## Validação

O índice calculado aqui foi comparado com o publicado no *Panorama do
Sistema de Consórcios* do Banco Central, data-base dezembro de 2024
(consulta Q8).

| Recorte | Calculado | Panorama BCB | Confere |
|---|---|---|---|
| Total do sistema | 48,6% | 48,6% | sim |
| Bens imóveis (segmento 1) | 56,9% | 56,9% | sim |
| Automóveis (segmento 3) | 46,8% | 46,8% | sim |
| Motocicletas (segmento 4) | 48,1% | 48,1% | sim |

Os quatro recortes reproduzem exatamente os valores publicados. A
carga, a definição de cotas ativas (contempladas + não contempladas) e
o cálculo do índice estão corretos.

A conferência também confirmou a correspondência entre os códigos de
segmento do arquivo e os subsegmentos usados pelo Panorama: o segmento
3 corresponde a automóveis e o 4 a motocicletas.

## Limitações

- Os dados são **agregados** por administradora, grupo e UF. Não há
  informação em nível de cota ou consorciado, o que impede análise de
  comportamento individual.
- A comparação entre tipos de administradora sofre efeito de
  composição: mix de segmento diferente produz índice diferente por
  razões alheias à gestão. Por isso a comparação é feita dentro do
  mesmo segmento.
- A classificação em `dim_administradora` é critério do autor. As
  administradoras pequenas e regionais foram agrupadas em Independente
  sem verificação individual de controle societário.
- **O mapeamento da classificação usa o nome da administradora, não o
  CNPJ.** Nomes mudam entre data-bases: a Cooperativa Mista Roma aparece
  como "COOPERATIVA MISTA ROMA (EX-JOCKEY" em 2026 e "COOP MISTA ROMA
  (ANTIGA JOCKEY" em 2024, e cai em categorias diferentes conforme o
  período. Chavear por CNPJ corrigiria isso.
- **A série temporal tem lacuna entre dez/2024 e jan/2026.** A função
  `LAG` compara com a linha anterior sem saber disso, então a variação
  calculada para jan/2026 (+13,2%) cobre treze meses, não um. O número
  está correto e a leitura seria errada — só as variações de fev a
  jun/2026 são mensais.
- O índice de exclusão é um **estoque acumulado** desde a constituição
  dos grupos, não uma taxa do período. Carteiras com grupos mais antigos
  carregam mais exclusão histórica, o que pode explicar parte das
  diferenças observadas entre tipos de administradora.

## Resultados

### Exclusão por tipo de administradora (jun/2026, consulta Q3)

Comparação feita **dentro do segmento**, para neutralizar o efeito de
mix de produto.

| Segmento | Tipo | Cotas ativas | Índice de exclusão |
|---|---|---|---|
| Bens imóveis | Cooperativa | 203.364 | 30,3% |
| Bens imóveis | Concessionária | 83.776 | 52,5% |
| Bens imóveis | Independente | 1.379.215 | 52,6% |
| Bens imóveis | Banco | 1.276.873 | 58,7% |
| Bens imóveis | Varejo | 53.892 | 63,4% |
| Automóveis | Cooperativa | 601.594 | 20,4% |
| Automóveis | Banco | 3.111.852 | 41,9% |
| Automóveis | Varejo | 94.107 | 45,0% |
| Automóveis | Independente | 1.236.573 | 55,3% |
| Automóveis | Máquinas e Implementos | 65.542 | 58,8% |
| Automóveis | Montadora | 314.670 | 63,4% |

Cooperativas apresentam o menor índice de exclusão nos dois maiores
segmentos, com margem larga: 30,3% contra 52,6% do segundo colocado em
imóveis, e 20,4% contra 41,9% em automóveis. O padrão se repete em dois
segmentos independentes.

Ver as limitações abaixo antes de interpretar como efeito de gestão: o
índice é estoque acumulado, e a idade média dos grupos não foi
controlada.

### Taxa de administração e exclusão (consulta Q6)

| Faixa de taxa | Cotas ativas | Índice de exclusão |
|---|---|---|
| até 12% | 7.069.588 | 23,3% |
| 12% a 16% | 19.265.852 | 34,1% |
| 16% a 20% | 25.694.521 | 53,2% |
| 20% ou mais | 37.633.386 | 53,8% |

Gradiente forte, mas **não é evidência de causalidade**: taxa alta se
concentra em imóveis e motocicletas, que têm dinâmica própria. O teste
adequado é comparar faixas dentro do mesmo segmento.

## Arquivos

```
docker-compose.yml    ambiente
01_schema.sql         schema, dimensões e fato
02_carga.sql          importação, limpeza e testes
03_classificacao.sql  classificação das administradoras
04_analise.sql        consultas de análise
dados/                CSVs do BCB (fora do Git)
```
