-- ============================================================
-- Carga: importação, limpeza e testes. Só SQL.
-- ============================================================

SET search_path TO consorcio, public;


-- ------------------------------------------------------------
-- 1. IMPORTAR O CSV
-- ------------------------------------------------------------
-- O arquivo do BCB vem em WIN1252 (não UTF-8), com ';' e
-- decimal por vírgula. O Postgres converte o encoding na
-- importação — não precisa mexer no Excel.
--
-- No terminal, com o container rodando:
--
--   docker compose exec postgres psql -U danilo -d consorcio \
--     -c "\copy consorcio.stg_segmentos FROM '/projeto/dados/segmentos.csv' \
--         WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'WIN1252')"
--
-- HEADER true descarta a primeira linha (a que começa com #).

-- Confira a importação:
SELECT count(*) AS linhas_staging FROM stg_segmentos;
SELECT * FROM stg_segmentos LIMIT 5;
-- Os acentos em nome_administradora devem estar corretos.
-- Se aparecer "ADEMICON ADM CONS S.A." legível, encoding OK.


-- ------------------------------------------------------------
-- 2. FUNÇÕES DE LIMPEZA
-- ------------------------------------------------------------
-- Devolvem NULL em vez de derrubar a carga quando o valor
-- não é conversível (célula vazia, traço, texto).

CREATE OR REPLACE FUNCTION limpar_inteiro(valor text)
RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN replace(btrim(coalesce(valor,'')), '.', '') ~ '^-?[0-9]+$'
        THEN replace(btrim(valor), '.', '')::integer
    END;
$$;

-- Decimal brasileiro: 24,02884 -> 24.02884
CREATE OR REPLACE FUNCTION limpar_decimal(valor text)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN replace(replace(btrim(coalesce(valor,'')), '.', ''), ',', '.')
             ~ '^-?[0-9]+(\.[0-9]+)?$'
        THEN replace(replace(btrim(valor), '.', ''), ',', '.')::numeric
    END;
$$;


-- ------------------------------------------------------------
-- 3. CHECAGEM ANTES DE CARREGAR
-- ------------------------------------------------------------
-- Duplicidade na chave. Se voltar alguma linha, PARE: a chave
-- (data_base, cnpj, segmento) não é única e o modelo precisa
-- mudar antes de carregar.
SELECT data_base, cnpj_administradora, codigo_segmento, count(*)
  FROM stg_segmentos
 GROUP BY 1,2,3
HAVING count(*) > 1;

-- Segmentos fora de 1-6 (linhas de rodapé, totais, sujeira)
SELECT codigo_segmento, count(*)
  FROM stg_segmentos
 WHERE btrim(coalesce(codigo_segmento,'')) !~ '^[1-6]$'
 GROUP BY 1;


-- ------------------------------------------------------------
-- 4. DIMENSÃO DE ADMINISTRADORA
-- ------------------------------------------------------------
-- lpad protege o CNPJ raiz: o Excel apaga zero à esquerda ao
-- salvar CSV, e 00123456 vira 123456. Aqui volta a 8 dígitos.
INSERT INTO dim_administradora (cnpj_administradora, nome_administradora)
SELECT DISTINCT
       lpad(regexp_replace(cnpj_administradora, '[^0-9]', '', 'g'), 8, '0'),
       btrim(nome_administradora)
  FROM stg_segmentos
 WHERE cnpj_administradora IS NOT NULL
   AND btrim(coalesce(codigo_segmento,'')) ~ '^[1-6]$'
ON CONFLICT (cnpj_administradora) DO NOTHING;


-- ------------------------------------------------------------
-- 5. FATO
-- ------------------------------------------------------------
INSERT INTO fato_segmento_mensal (
    data_base, cnpj_administradora, codigo_segmento,
    taxa_administracao,
    grupos_ativos, grupos_constituidos_mes, grupos_encerrados_mes,
    cotas_comercializadas_mes, cotas_excluidas_a_comercializar,
    cotas_ativas_contempladas, cotas_ativas_nao_contempladas,
    cotas_contempladas_mes, cotas_ativas_em_dia,
    cotas_contempladas_inadimpl, cotas_nao_contempladas_inadimpl,
    cotas_excluidas, cotas_ativas_quitadas, cotas_credito_pendente)
SELECT to_date(btrim(data_base), 'YYYYMM'),
       lpad(regexp_replace(cnpj_administradora, '[^0-9]', '', 'g'), 8, '0'),
       btrim(codigo_segmento)::smallint,
       limpar_decimal(taxa_administracao),
       limpar_inteiro(grupos_ativos),
       limpar_inteiro(grupos_constituidos_mes),
       limpar_inteiro(grupos_encerrados_mes),
       limpar_inteiro(cotas_comercializadas_mes),
       limpar_inteiro(cotas_excluidas_a_comercializar),
       limpar_inteiro(cotas_ativas_contempladas),
       limpar_inteiro(cotas_ativas_nao_contempladas),
       limpar_inteiro(cotas_contempladas_mes),
       limpar_inteiro(cotas_ativas_em_dia),
       limpar_inteiro(cotas_contempladas_inadimpl),
       limpar_inteiro(cotas_nao_contempladas_inadimpl),
       limpar_inteiro(cotas_excluidas),
       limpar_inteiro(cotas_ativas_quitadas),
       limpar_inteiro(cotas_credito_pendente)
  FROM stg_segmentos
 WHERE btrim(coalesce(codigo_segmento,'')) ~ '^[1-6]$'
ON CONFLICT (data_base, cnpj_administradora, codigo_segmento) DO NOTHING;


-- ------------------------------------------------------------
-- 6. TESTES DE CARGA
-- ------------------------------------------------------------
-- Rodar SEMPRE. Resultado inesperado aqui invalida tudo adiante.

-- 6.1 Contagem: fato deve bater com staging menos as linhas
--     descartadas pelo filtro de segmento.
SELECT (SELECT count(*) FROM stg_segmentos)        AS staging,
       (SELECT count(*) FROM fato_segmento_mensal) AS fato;

-- 6.2 Conversão numérica falhou em algum lugar?
SELECT count(*) FILTER (WHERE cotas_ativas_contempladas IS NULL)     AS contempl_nula,
       count(*) FILTER (WHERE cotas_ativas_nao_contempladas IS NULL) AS nao_contempl_nula,
       count(*) FILTER (WHERE cotas_excluidas IS NULL)               AS excluidas_nula,
       count(*) FILTER (WHERE taxa_administracao IS NULL)            AS taxa_nula
  FROM fato_segmento_mensal;

-- 6.3 CONSISTÊNCIA INTERNA — o teste mais importante.
--     O arquivo traz as cotas ativas repartidas de duas formas:
--       por contemplação: contempladas + não contempladas
--       por adimplência : em dia + inadimplentes
--     As duas somas têm que dar o mesmo número.
--     Toda linha que aparecer aqui é divergência do próprio
--     arquivo e precisa ser entendida antes de analisar.
SELECT a.nome_administradora,
       f.codigo_segmento,
       f.cotas_ativas AS por_contemplacao,
       coalesce(f.cotas_ativas_em_dia,0)
     + coalesce(f.cotas_contempladas_inadimpl,0)
     + coalesce(f.cotas_nao_contempladas_inadimpl,0) AS por_adimplencia
  FROM fato_segmento_mensal f
  JOIN dim_administradora a USING (cnpj_administradora)
 WHERE f.cotas_ativas <> coalesce(f.cotas_ativas_em_dia,0)
                       + coalesce(f.cotas_contempladas_inadimpl,0)
                       + coalesce(f.cotas_nao_contempladas_inadimpl,0);

-- 6.4 Panorama por data-base
SELECT data_base,
       count(*)                        AS linhas,
       count(DISTINCT cnpj_administradora) AS administradoras,
       sum(cotas_ativas)               AS cotas_ativas,
       sum(cotas_excluidas)            AS cotas_excluidas
  FROM fato_segmento_mensal
 GROUP BY data_base
 ORDER BY data_base;


-- ------------------------------------------------------------
-- 7. PRÓXIMO PASSO
-- ------------------------------------------------------------
-- A classificação das administradoras está no 03_classificacao.sql.
