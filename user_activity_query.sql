WITH
  account_metrics AS (
    -- 1️⃣ Рахуємо метрики по акаунтах
    -- На цьому кроці отримуємо кількість акаунтів у розрізі:
    -- date + country + account_id + send_interval
    SELECT
      s.date,
      sp.country,
      a.is_verified,
      a.is_unsubscribed,
      a.send_interval,
      COUNT(DISTINCT a.id) AS account_cnt
    FROM DA.account a
    JOIN DA.account_session acs
      ON a.id = acs.account_id
    JOIN DA.session s
      ON acs.ga_session_id = s.ga_session_id
    JOIN DA.session_params sp
      ON acs.ga_session_id = sp.ga_session_id
    GROUP BY 1, 2, 3, 4, 5
  ),
  email_metrics AS (
    -- 3️⃣ Рахуємо метрики по email
    -- Отримуємо кількість:
    -- відправлених, відкритих і кліків (visit)
    -- у тих самих розрізах
    SELECT
      date_add(s.date, INTERVAL es.sent_date DAY) AS date,
      sp.country,
      a.is_verified,
      a.is_unsubscribed,
      a.send_interval,
      COUNT(DISTINCT es.id_message) AS sent_msg,
      COUNT(DISTINCT eo.id_message) AS open_msg,
      COUNT(DISTINCT ev.id_message) AS visit_msg,
    FROM DA.email_sent es
    LEFT JOIN DA.email_open eo
      ON es.id_message = eo.id_message
    LEFT JOIN DA.email_visit ev
      ON es.id_message = ev.id_message
    JOIN DA.account_session acs
      ON es.id_account = acs.account_id
    JOIN DA.session s
      ON acs.ga_session_id = s.ga_session_id
    JOIN DA.session_params sp
      ON acs.ga_session_id = sp.ga_session_id
    JOIN DA.account a
      ON acs.account_id = a.id
    GROUP BY 1, 2, 3, 4, 5
  ),
  union_metrics AS (
    -- 4️⃣ Об’єднуємо метрики через UNION ALL
    -- Приводимо обидва набори до однієї структури:
    -- account метрики + email метрики
    SELECT
      date,
      country,
      account_metrics.is_verified,
      account_metrics.is_unsubscribed,
      send_interval,
      account_cnt,
      0 AS sent_msg,
      0 AS open_msg,
      0 AS visit_msg
    FROM account_metrics
    UNION ALL
    SELECT
      date,
      country,
      email_metrics.is_verified,
      email_metrics.is_unsubscribed,
      send_interval,
      0 AS account_cnt,
      sent_msg,
      open_msg,
      visit_msg
    FROM email_metrics
  ),
  final_metrics AS (
    -- 5️⃣ Агрегуємо після UNION
    -- Складаємо метрики назад в один рядок
    SELECT
      date,
      country,
      is_verified,
      is_unsubscribed,
      send_interval,
      SUM(account_cnt) AS account_cnt,
      SUM(sent_msg) AS sent_msg,
      SUM(open_msg) AS open_msg,
      SUM(visit_msg) AS visit_msg
    FROM union_metrics
    GROUP BY 1, 2, 3, 4, 5
  ),
  country_totals AS (
    -- 6️⃣ Рахуємо тотали по країнам (через window functions)
    -- НЕ робимо окремий GROUP BY, а використовуємо OVER()
    SELECT
      *,
      SUM(account_cnt) OVER (PARTITION BY country) AS total_country_account_cnt,
      SUM(sent_msg) OVER (PARTITION BY country) AS total_country_sent_cnt
    FROM final_metrics
  ),
  ranked AS (
    -- 7️⃣ Ранжуємо країни
    -- Використовуємо DENSE_RANK (як в умові)
    SELECT
      *,
      DENSE_RANK()
        OVER (ORDER BY total_country_account_cnt DESC) AS rank_account,
      DENSE_RANK() OVER (ORDER BY total_country_sent_cnt DESC) AS rank_sent
    FROM country_totals
  )


-- 8️⃣ Фінальний результат
-- Беремо ТОП-10 по будь-якому з ранків
SELECT *
FROM ranked
WHERE
  rank_account <= 10
  OR rank_sent <= 10;
