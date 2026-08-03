SELECT 
  t.id AS ID,
  t.name AS Chamado,
  
  -- 📅 Data de Abertura (Formatada diretamente como texto no horário do banco)
  DATE_FORMAT(t.date, '%Y-%m-%d %H:%i:%s') AS Data_Abertura,

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
  
  -- 📅 Data de Fechamento (Formatada diretamente como texto no horário do banco)
  DATE_FORMAT(COALESCE(t.closedate, t.solvedate, t.date_mod), '%Y-%m-%d %H:%i:%s') AS Data_Fechamento,
  
  -- ⏱️ Tempo Total de Atendimento
  SEC_TO_TIME(TIMESTAMPDIFF(SECOND, t.date, COALESCE(t.closedate, t.solvedate, t.date_mod))) AS Tempo_Total_Atendimento,
  
  -- 🚨 Status do SLA
  CASE 
    WHEN t.time_to_resolve IS NULL THEN 'Sem SLA Definido'
    WHEN COALESCE(t.solvedate, t.closedate, t.date_mod) <= DATE_ADD(t.time_to_resolve, INTERVAL t.waiting_duration SECOND) THEN '✅ Dentro do SLA'
    ELSE '❌ SLA Estourado'
  END AS Status_SLA

FROM glpi_tickets t
LEFT JOIN glpi_tickets_users tu 
  ON tu.tickets_id = t.id AND tu.type = 2
LEFT JOIN glpi_users u 
  ON u.id = tu.users_id

WHERE t.status IN (5, 6) -- Solucionados (5) ou Fechados (6)
  AND t.is_deleted = 0
  -- Filtra chamados alterados/fechados HOJE
  AND DATE(COALESCE(t.closedate, t.solvedate, t.date_mod)) = CURDATE()

ORDER BY COALESCE(t.closedate, t.solvedate, t.date_mod) DESC;