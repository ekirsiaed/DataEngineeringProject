#1. Which production genres account for the highest attendance and ticket revenue?

SELECT
    c.classification_name AS genre,
    SUM(f.attendance) AS total_attendance,
    SUM(f.ticket_revenue_eur) AS total_ticket_revenue_eur
FROM FactRepertoire f
JOIN DimClassification c
    ON c.classification_key = f.classification_key
WHERE c.reporting_level = 'genre'
GROUP BY c.classification_key, c.classification_name
ORDER BY total_attendance DESC NULLS LAST,
         total_ticket_revenue_eur DESC NULLS LAST;


#2. Which productions have the highest attendance per performance?

SELECT
    t.theatre_code,
    p.production_code,
    p.production_title,
    SUM(f.attendance) AS total_attendance,
    SUM(f.performance_count) AS total_performances,
    ROUND(
        SUM(f.attendance)::NUMERIC
        / NULLIF(SUM(f.performance_count), 0),
        2
    ) AS attendance_per_performance
FROM FactRepertoire f
JOIN DimTheatre t ON t.theatre_key = f.theatre_key
JOIN DimProduction p ON p.production_key = f.production_key
WHERE f.attendance IS NOT NULL
  AND f.performance_count IS NOT NULL
GROUP BY t.theatre_code, p.production_code, p.production_title
HAVING SUM(f.performance_count) > 0
ORDER BY attendance_per_performance DESC
LIMIT 20;


#3. How do annual attendance and ticket revenue trends differ between theatres?

SELECT
    t.theatre_code,
    y.reporting_year,
    SUM(f.attendance) AS annual_attendance,
    SUM(f.ticket_revenue_eur) AS annual_ticket_revenue_eur
FROM FactRepertoire f
JOIN DimTheatre t ON t.theatre_key = f.theatre_key
JOIN DimYear y ON y.year_key = f.year_key
GROUP BY t.theatre_code, y.reporting_year
ORDER BY t.theatre_code, y.reporting_year;


#4. How does ticket revenue per performance differ between target audiences?

SELECT
    a.audience_name,
    SUM(f.ticket_revenue_eur) AS total_ticket_revenue_eur,
    SUM(f.performance_count) AS covered_performances,
    ROUND(
        SUM(f.ticket_revenue_eur)
        / NULLIF(SUM(f.performance_count), 0),
        2
    ) AS ticket_revenue_per_performance_eur
FROM FactRepertoire f
JOIN DimAudience a ON a.audience_key = f.audience_key
WHERE f.ticket_revenue_eur IS NOT NULL
  AND f.performance_count IS NOT NULL
GROUP BY a.audience_key, a.audience_name
HAVING SUM(f.performance_count) > 0
ORDER BY ticket_revenue_per_performance_eur DESC;


#5. How do productions based on Estonian and foreign texts differ in attendance per performance?

SELECT
    p.text_origin_group,
    SUM(f.attendance) AS total_attendance,
    SUM(f.performance_count) AS total_performances,
    ROUND(
        SUM(f.attendance)::NUMERIC
        / NULLIF(SUM(f.performance_count), 0),
        2
    ) AS attendance_per_performance
FROM FactRepertoire f
JOIN DimProduction p ON p.production_key = f.production_key
WHERE p.text_origin_group IN ('Estonian', 'Foreign')
  AND f.attendance IS NOT NULL
  AND f.performance_count IS NOT NULL
GROUP BY p.text_origin_group
HAVING SUM(f.performance_count) > 0;


#6. How does the distribution of attendance across production types in individual theatres compare with the national distribution in the same year?

WITH theatre_totals AS (
    SELECT
        f.year_key,
        t.theatre_code,
        f.theatre_category_key,
        c.production_type_code,
        SUM(f.attendance) AS attendance
    FROM FactRepertoire f
    JOIN DimTheatre t ON t.theatre_key = f.theatre_key
    JOIN DimClassification c
        ON c.classification_key = f.classification_key
    WHERE c.reporting_level IN ('type', 'genre')
      AND c.production_type_code IS NOT NULL
    GROUP BY
        f.year_key, t.theatre_code,
        f.theatre_category_key, c.production_type_code
),
national_totals AS (
    SELECT
        f.year_key,
        f.theatre_category_key,
        c.production_type_code,
        SUM(f.attendance) AS attendance
    FROM FactNational f
    JOIN DimClassification c
        ON c.classification_key = f.classification_key
    WHERE c.reporting_level = 'type'
      AND c.production_type_code IS NOT NULL
    GROUP BY
        f.year_key, f.theatre_category_key,
        c.production_type_code
),
theatre_shares AS (
    SELECT *,
        100.0 * attendance
        / NULLIF(
            SUM(attendance) OVER (
                PARTITION BY year_key, theatre_code,
                             theatre_category_key
            ), 0
        ) AS attendance_share_pct
    FROM theatre_totals
),
national_shares AS (
    SELECT *,
        100.0 * attendance
        / NULLIF(
            SUM(attendance) OVER (
                PARTITION BY year_key, theatre_category_key
            ), 0
        ) AS attendance_share_pct
    FROM national_totals
)
SELECT
    y.reporting_year,
    t.theatre_code,
    cat.category_name,
    t.production_type_code,
    ROUND(t.attendance_share_pct, 2) AS theatre_share_pct,
    ROUND(n.attendance_share_pct, 2) AS national_share_pct,
    ROUND(
        t.attendance_share_pct - n.attendance_share_pct,
        2
    ) AS difference_percentage_points
FROM theatre_shares t
JOIN national_shares n
    ON n.year_key = t.year_key
   AND n.theatre_category_key = t.theatre_category_key
   AND n.production_type_code = t.production_type_code
JOIN DimYear y ON y.year_key = t.year_key
JOIN DimTheatreCategory cat
    ON cat.theatre_category_key = t.theatre_category_key
ORDER BY
    y.reporting_year, t.theatre_code, t.production_type_code;
