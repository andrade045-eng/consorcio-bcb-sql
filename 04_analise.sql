-- ============================================================
-- Consultas de análise. Layout real, data-base 202606.
-- ============================================================
-- Índice de exclusão (IE) = excluídas / (ativas + excluídas)
-- Cotas ativas é coluna calculada: contempladas + não contempladas
-- ============================================================

SET search_path TO consorcio, public;


-- ------------------------------------------------------------
-- Q1. IE consolidado por data-base  >>> QUERY DE VALIDAÇÃO <<<
--     Comparar com o número publicado no Panorama do BCB.
-- ------------------------------------------------------------
SELECT data_base,
       sum(cotas_ativas)    AS cotas_ativas,
       sum(cotas_excluidas) AS cotas_excluidas,
       round(100.0 * sum(cotas_excluidas)
             / nullif(sum(cotas_ativas) + sum(cotas_excluidas), 0), 1) AS ie_pct
  FROM fato_segmento_mensal
 GROUP BY data_base
 ORDER BY data_base;


-- ------------------------------------------------------------
-- Q2. IE por segmento
-- ------------------------------------------------------------
SELECT s.descricao AS segmento,
       sum(f.cotas_ativas) AS cotas_ativas,
       round(100.0 * sum(f.cotas_excluidas)
             / nullif(sum(f.cotas_ativas) + sum(f.cotas_excluidas), 0), 1) AS ie_pct
  FROM fato_segmento_mensal f
  JOIN dim_segmento s USING (codigo_segmento)
 GROUP BY 1
 ORDER BY ie_pct DESC;


-- ------------------------------------------------------------
-- Q3. IE por tipo de administradora DENTRO de cada segmento
--     >>> A CONSULTA QUE SÓ VOCÊ CONSEGUE ESCREVER <<<
--     Comparar dentro do segmento é obrigatório: tipos com mix
--     diferente de bens teriam IE diferente sem que a gestão
--     tivesse qualquer papel nisso.
--     Corte de 10 mil cotas para não comparar com base pequena.
-- ------------------------------------------------------------
SELECT s.descricao AS segmento,
       a.tipo_administradora,
       count(DISTINCT a.cnpj_administradora) AS administradoras,
       sum(f.cotas_ativas) AS cotas_ativas,
       round(100.0 * sum(f.cotas_excluidas)
             / nullif(sum(f.cotas_ativas) + sum(f.cotas_excluidas), 0), 1) AS ie_pct
  FROM fato_segmento_mensal f
  JOIN dim_segmento s       USING (codigo_segmento)
  JOIN dim_administradora a USING (cnpj_administradora)
 WHERE f.data_base = (SELECT max(data_base) FROM fato_segmento_mensal)
 GROUP BY 1,2
HAVING sum(f.cotas_ativas) >= 10000
 ORDER BY s.descricao, ie_pct;


-- ------------------------------------------------------------
-- Q4. Inadimplência por tipo de administradora
--     O arquivo separa inadimplência de contempladas e de não
--     contempladas — distinção relevante: quem já recebeu o bem
--     e para de pagar é risco diferente de quem ainda espera.
-- ------------------------------------------------------------
SELECT a.tipo_administradora,
       sum(f.cotas_ativas) AS cotas_ativas,
       round(100.0 * sum(f.cotas_contempladas_inadimpl)
             / nullif(sum(f.cotas_ativas_contempladas), 0), 1)
           AS inadimpl_contempladas_pct,
       round(100.0 * sum(f.cotas_nao_contempladas_inadimpl)
             / nullif(sum(f.cotas_ativas_nao_contempladas), 0), 1)
           AS inadimpl_nao_contempladas_pct
  FROM fato_segmento_mensal f
  JOIN dim_administradora a USING (cnpj_administradora)
 WHERE f.data_base = (SELECT max(data_base) FROM fato_segmento_mensal)
 GROUP BY 1
 ORDER BY inadimpl_nao_contempladas_pct DESC;


-- ------------------------------------------------------------
-- Q5. Ranking de administradoras dentro do segmento
--     Técnica: RANK com partição
-- ------------------------------------------------------------
SELECT s.descricao AS segmento,
       a.nome_administradora,
       a.tipo_administradora,
       f.cotas_ativas,
       rank() OVER (PARTITION BY f.codigo_segmento
                    ORDER BY f.cotas_ativas DESC) AS posicao
  FROM fato_segmento_mensal f
  JOIN dim_segmento s       USING (codigo_segmento)
  JOIN dim_administradora a USING (cnpj_administradora)
 WHERE f.data_base = (SELECT max(data_base) FROM fato_segmento_mensal)
   AND f.cotas_ativas >= 5000
 ORDER BY s.descricao, posicao;


-- ------------------------------------------------------------
-- Q6. Taxa de administração e exclusão andam juntas?
--     Faixas de taxa contra IE médio. Não prova causalidade —
--     taxa alta concentra-se em segmentos específicos.
-- ------------------------------------------------------------
SELECT CASE
         WHEN taxa_administracao <  12 THEN 'até 12%'
         WHEN taxa_administracao <  16 THEN '12% a 16%'
         WHEN taxa_administracao <  20 THEN '16% a 20%'
         ELSE '20% ou mais'
       END AS faixa_taxa,
       count(*)            AS registros,
       sum(cotas_ativas)   AS cotas_ativas,
       round(100.0 * sum(cotas_excluidas)
             / nullif(sum(cotas_ativas) + sum(cotas_excluidas), 0), 1) AS ie_pct
  FROM fato_segmento_mensal
 WHERE taxa_administracao IS NOT NULL
 GROUP BY 1
 ORDER BY 1;


-- ------------------------------------------------------------
-- Q7. Série temporal — SÓ FUNCIONA COM VÁRIAS DATAS-BASE
--     Técnica: window function (LAG)
--     Rodar depois de carregar mais meses.
-- ------------------------------------------------------------
WITH mensal AS (
    SELECT data_base, sum(cotas_ativas) AS cotas_ativas
      FROM fato_segmento_mensal
     GROUP BY data_base
)
SELECT data_base,
       cotas_ativas,
       cotas_ativas - lag(cotas_ativas) OVER (ORDER BY data_base) AS variacao,
       round(100.0 * (cotas_ativas - lag(cotas_ativas) OVER (ORDER BY data_base))
             / nullif(lag(cotas_ativas) OVER (ORDER BY data_base), 0), 2) AS variacao_pct
  FROM mensal
 ORDER BY data_base;


-- ------------------------------------------------------------
-- Q8. VALIDAÇÃO CONTRA O PANORAMA 2024
--     Números publicados pelo BCB para dez/2024:
--       Total     48,6%
--       Imóveis   56,9%  (segmento 1)
--       Automóveis 46,8% (segmento 3)
-- ------------------------------------------------------------
SELECT coalesce(s.descricao, 'TOTAL') AS segmento,
       sum(f.cotas_ativas)    AS cotas_ativas,
       sum(f.cotas_excluidas) AS cotas_excluidas,
       round(100.0 * sum(f.cotas_excluidas)
             / nullif(sum(f.cotas_ativas) + sum(f.cotas_excluidas), 0), 1) AS ie_pct
  FROM fato_segmento_mensal f
  LEFT JOIN dim_segmento s USING (codigo_segmento)
 WHERE f.data_base = '2024-12-01'
 GROUP BY ROLLUP (s.descricao)
 ORDER BY 1;
