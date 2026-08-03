SELECT 
  t.id AS ID,
  t.name AS Chamado,

  -- 📅 Data de Abertura (Formatada diretamente como texto para travar o fuso)
  DATE_FORMAT(t.date, '%Y-%m-%d %H:%i:%s') AS Data_Abertura,

  -- 📊 Status do Chamado
  CASE 
    WHEN t.status = 1 THEN '🆕 NOVO'
    WHEN t.status = 2 THEN '⚙️ EM ATENDIMENTO (PROP.)'
    WHEN t.status = 3 THEN '⚙️ EM ATENDIMENTO (PLAN.)'
    WHEN t.status = 4 THEN '⏳ PENDENTE'
    WHEN t.status = 5 THEN '✅ SOLUCIONADO'
    WHEN t.status = 6 THEN '🔒 FECHADO'
    ELSE 'OUTRO'
  END AS Status,

  -- ⚠️ Prioridade
  CASE 
    WHEN t.priority = 5 THEN '🔥 MUITO ALTA / CRÍTICO'
    WHEN t.priority = 4 THEN '🔴 ALTA'
    WHEN t.priority = 3 THEN '🟡 MÉDIA'
    WHEN t.priority = 2 THEN '🔵 BAIXA'
    WHEN t.priority = 1 THEN '🟢 MUITO BAIXA'
    ELSE 'MÉDIA'
  END AS Prioridade,

  COALESCE(u.name, 'SEM TECNICO') AS Tecnico,

  -- ⏱ Tempo Aberto Formatado (Dias + HH:MM:SS)
  CONCAT(
    TIMESTAMPDIFF(DAY, t.date, NOW()), ' dias, ',
    TIME_FORMAT(SEC_TO_TIME(MOD(TIMESTAMPDIFF(SECOND, t.date, NOW()), 86400)), '%H:%i:%s')
  ) AS Tempo_Aberto

FROM glpi_tickets t
LEFT JOIN glpi_tickets_users tu 
  ON tu.tickets_id = t.id AND tu.type = 2
LEFT JOIN glpi_users u 
  ON u.id = tu.users_id

WHERE t.status NOT IN (5, 6) -- Exclui Solucionados e Fechados
  AND t.is_deleted = 0

-- Ordenação: Coloca 'Pendente' por último e prioriza os prazos mais críticos do SLA
ORDER BY 
  CASE WHEN t.status = 4 THEN 1 ELSE 0 END ASC,
  TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(t.time_to_resolve, INTERVAL COALESCE(t.waiting_duration, 0) SECOND)) ASC;