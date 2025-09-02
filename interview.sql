/*
# ОГЛАВЛЕНИЕ: 
## SQL базовый и расширенный

[v] Пример использования Common Table Expressions (WITH ... AS) и LEFT JOIN. 
[v] Создание view и materialized view для средней зарплаты по отделу из запроса выше.
[v] Пример derived table (подзапрос во FROM)
[v] Создание индекса
[v] Создание hash-индекса 
[v] пример согласованного отката двух изменений
[v] пример согласованного коммита двух изменений
[v] Пример отката до изменений до точки SAVEPOINT, и коммита предыдущих
[v] Временные таблицы (Temporary tables)
[v] Разница между JOIN, UNION, UNION ALL
[v] Индексы и селективность (включая объяснение, как она влияет на планы выполнения)
[v] Анализ планов выполнения (EXPLAIN PLAN)
[v] Мониторинг медленных запросов и вынесение метрик
[v] Комлесная работа с группировкой SELECT → FROM → WHERE → GROUP BY → HAVING
[v] Использование агрегатных функций (в первом примере)
[v] Сравнение IN vs EXISTS vs JOIN
[v] CASE WHEN внутри SELECT
[v] Оконные функции Rank(), dense_rank() Row_number(), 


## Транзакции и управление состоянием
[v] Понятие сериализации (serializability)
[v] ACID: Atomicity, Consistency, Isolation, Durability - теория
[v] Уровни изоляции: Read Committed, Repeatable Read, Serializable - теория 
[v] DEADLOCK, блокировки и конкурентный доступ

[v] SAVEPOINT, COMMIT и ROLLBACK
[v] Автоматические коммиты при DDL

Процедурное программирование в Oracle
[v] Функции и методы в PL/SQL - IN/OUT параметры, возвращаеемые значения
*/

/* 
Пример использования Common Table Expressions (WITH ... AS) и LEFT JOIN.

Созданный CTE позволяет рассчитать среднюю зарплату по отделу, а затем через LEFT JOIN вывести сотрудников, чья зарплата выше средней по своему отделу.
*/
WITH avg_sal_per_dept AS (
  SELECT deptno, AVG(sal) AS avg_sal
  FROM emp
  GROUP BY deptno
)
SELECT 
  e.empno,
  e.ename,
  e.deptno,
  e.sal,
  av.avg_sal
FROM emp e
LEFT JOIN avg_sal_per_dept av ON e.deptno = av.deptno
WHERE e.sal > av.avg_sal;

/*
Создание view и materialized view для средней зарплаты по отделу из запроса выше.
Обычное представление всегда актуально, а материализованное пересчитывается каждую ночь, чтобы ускорить работу с агрегатами и снизить нагрузку на выборки из таблицы.
*/
CREATE OR REPLACE VIEW emp_above_avg_view AS
WITH avg_sal_per_dept AS (
    SELECT deptno, AVG(sal) AS avg_sal
    FROM emp
    GROUP BY deptno
);

CREATE MATERIALIZED VIEW emp_above_avg_mv
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH TRUNC(SYSDATE) + 3/24
NEXT TRUNC(SYSDATE + 1) + 3/24
AS
WITH avg_sal_per_dept AS (
    SELECT deptno, AVG(sal) AS avg_sal
    FROM emp
    GROUP BY deptno
)
SELECT 
  e.empno,
  e.ename,
  e.deptno,
  e.sal,
  av.avg_sal
FROM emp e
LEFT JOIN avg_sal_per_dept av ON e.deptno = av.deptno
WHERE e.sal > av.avg_sal;

/*
Пример derived table (подзапрос во FROM) — отделы, где сотрудников больше 5.
Удобно для фильтрации по агрегированным данным прямо “на лету”.
*/
SELECT *
FROM (
  SELECT deptno, COUNT(*) AS emp_count
  FROM emp
  GROUP BY deptno
) d
WHERE d.emp_count > 5;

/*
Создание индекса по фамилии сотрудника.
Позволяет ускорить поиск и сортировку по этому полю в больших таблицах.
*/
CREATE INDEX emp_ename_idx ON emp(ename);

/*
Создание hash-индекса по номеру департамента.
*/
CREATE INDEX emp_deptno_hash_idx ON emp(deptno) INDEXTYPE IS HASH;

/*
Временные таблицы (Oracle Global Temporary Tables, GTT)
Данные временные, объект постоянный. Ниже пример с хранением строк на время СЕССИИ.
Checklist:
  [v] Создание GTT (ON COMMIT PRESERVE ROWS)
  [v] Вставка тестовых строк
  [v] Запрос с фильтром
  [v] Индекс по колонке amount (опционально)
  [v] Агрегация
*/
CREATE GLOBAL TEMPORARY TABLE sales_tmp_sess (
  id         NUMBER PRIMARY KEY,
  amount     NUMBER(12,2),
  created_at TIMESTAMP
) ON COMMIT PRESERVE ROWS; -- строки сохраняются до конца сессии

-- Вставка примеров
INSERT INTO sales_tmp_sess (id, amount, created_at) VALUES (1, 100.00, SYSTIMESTAMP);
INSERT INTO sales_tmp_sess (id, amount, created_at) VALUES (2, 45.50,  SYSTIMESTAMP);
INSERT INTO sales_tmp_sess (id, amount, created_at) VALUES (3, 250.00, SYSTIMESTAMP);

-- Запрос с фильтром
SELECT id, amount
FROM sales_tmp_sess
WHERE amount > 50;

-- Индекс (ускоряет выборки/сортировки по amount)
CREATE INDEX sales_tmp_sess_amt_idx ON sales_tmp_sess(amount);

-- Агрегация
SELECT COUNT(*) AS cnt_over_50, SUM(amount) AS total_over_50
FROM sales_tmp_sess
WHERE amount > 50;

-- Примечания:
-- 1) ON COMMIT PRESERVE ROWS — строки остаются в таблице в рамках сессии (COMMIT их не очищает).
--    Если требуется очистка при COMMIT, создавайте GTT с ON COMMIT DELETE ROWS.
-- 2) DDL над GTT — объект остаётся, но данные индивидуальны для каждой сессии.
-- 3) Явный DROP TABLE для GTT обычно не нужен в боевом коде; объект создаётся один раз миграцией.

/*
пример согласованного отката двух изменений - два insert + rollback
*/

INSERT INTO emp (empno, ename, deptno, sal)
VALUES (9999, 'NIKITA LEONOV', 10, 140000);
INSERT INTO emp (empno, ename, deptno, sal)
VALUES (10000, 'JOHN SNOW', 20, 6500);
ROLLBACK;

/*
пример согласованного коммита двух изменений - два insert + commit
*/
INSERT INTO emp (empno, ename, deptno, sal)
VALUES (9999, 'PREV CANDIDATE', 10, 140000);
INSERT INTO emp (empno, ename, deptno, sal)
VALUES (10000, 'JOHN SNOW', 20, 6500);
COMMIT;


/*
пример отката до SAVEPOINT -  insert, savepoint, insert, rollback to savepoint,  commit;
*/
-- Начинаем транзакцию автоматом  
INSERT INTO emp (empno, ename, deptno, sal)
VALUES (9999, 'NIKITA LEONOV', 10, 150000);

-- Устанавливаем точку сохранения 
SAVEPOINT sp_after_first_candidate;

-- Вставляем вторую запись — тестовую  
INSERT INTO emp (empno, ename, deptno, sal)
VALUES (10000, 'TEST USER', 20, 6500);

-- Откатываем изменения до точки SAVEPOINT — откатит только вторую вставку 
ROLLBACK TO SAVEPOINT sp_after_first_candidate;

-- Фиксируем изменения — в таблице останется только запись Никиты Леонова 
COMMIT;
-- Функции RANK() и DENSE_RANK() Вывожу рейтинг сотрудников по зарплате внутри каждого отдела.
SELECT 
  empno,
  ename,
  deptno,
  sal,
  RANK() OVER (PARTITION BY deptno ORDER BY sal DESC) AS sal_rank,
  DENSE_RANK() OVER (PARTITION BY deptno ORDER BY sal DESC) AS sal_dense_rank
FROM emp;

/*
Разница между JOIN, UNION, UNION ALL
*/
-- JOIN соединяет строки по условию (колонки могут различаться), возвращает объединённые столбцы
SELECT e.empno, e.ename, d.dname
FROM emp e
JOIN dept d ON d.deptno = e.deptno;

-- UNION удаляет дубликаты (доп. сортировка/уникализация), колонки и типы должны совпадать по количеству/совместимости
SELECT deptno FROM emp
UNION
SELECT deptno FROM dept;

-- UNION ALL не удаляет дубликаты — быстрее
SELECT deptno FROM emp
UNION ALL
SELECT deptno FROM dept;

/*
Индексы и селективность
Высокоселективный предикат (мало строк) — индекс полезен; низкоселективный (много строк) — возможен full scan.
*/
-- Индекс по зарплате
CREATE INDEX emp_sal_idx ON emp(sal);

-- Высокая селективность: sal > 100000 (для небольшого процента сотрудников)
SELECT /* селективность высокая */ empno, sal FROM emp WHERE sal > 100000;

-- Низкая селективность: deptno IN (10,20,30) — вероятно много строк
SELECT /* селективность низкая */ empno, deptno FROM emp WHERE deptno IN (10,20,30);

/*
EXPLAIN PLAN (анализ плана выполнения)
*/
EXPLAIN PLAN FOR
SELECT e.empno, e.ename FROM emp e WHERE e.sal > 100000;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

/*
Мониторинг медленных запросов и метрик (упрощённо)
*/
-- Пример: найти последние «дорогие» запросы по cpu_time/elapsed_time
SELECT sql_id, executions, cpu_time, elapsed_time, sql_text
FROM v$sql
WHERE parsing_schema_name = USER
ORDER BY elapsed_time DESC FETCH FIRST 5 ROWS ONLY;

/*
Комлесная работа с группировкой SELECT → FROM → WHERE → GROUP BY → HAVING
*/
-- WHERE фильтрует ДО агрегации, HAVING — ПОСЛЕ агрегации
SELECT d.deptno,
       COUNT(*) AS emp_cnt,
       AVG(e.sal) AS avg_sal
FROM dept d
JOIN emp e ON e.deptno = d.deptno
WHERE e.sal > 1000               -- фильтр до GROUP BY
GROUP BY d.deptno
HAVING COUNT(*) >= 3;            -- фильтр после агрегирования

/*
Сравнение IN vs EXISTS vs JOIN (анти/полусоединения)
*/
-- IN: читаемо, хорошо для небольших подмножеств
SELECT e.empno FROM emp e WHERE e.deptno IN (SELECT d.deptno FROM dept d WHERE d.loc = 'DALLAS');

-- EXISTS: часто эффективнее при коррелированных проверках
SELECT e.empno
FROM emp e
WHERE EXISTS (
  SELECT 1 FROM dept d WHERE d.deptno = e.deptno AND d.loc = 'DALLAS'
);

-- JOIN: используем, когда нужны данные обеих таблиц; для проверки существования можно SELECT DISTINCT
SELECT DISTINCT e.empno
FROM emp e
JOIN dept d ON d.deptno = e.deptno AND d.loc = 'DALLAS';

/*
CASE WHEN внутри SELECT
*/
SELECT empno,
       sal,
       CASE
         WHEN sal >= 100000 THEN 'HIGH'
         WHEN sal >= 50000 THEN 'MEDIUM'
         ELSE 'LOW'
       END AS sal_band
FROM emp;

/*
Понятие сериализации (serializability)
*/
-- В Oracle можно зафиксировать транзакцию в SERIALIZABLE для предотвращения фантомов (полной сериализации не всегда достигается)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Пример запроса под уровнем SERIALIZABLE
SELECT COUNT(*) FROM emp WHERE deptno = 10;
COMMIT;

/*
DEADLOCK, блокировки и конкурентный доступ (демонстрация сценария)
*/
-- Сессия 1:
-- UPDATE emp SET sal = sal + 100 WHERE empno = 7369; -- блокирует строку A
-- затем попытка UPDATE emp SET sal = sal + 100 WHERE empno = 7499; -- ждёт строку B
-- Сессия 2:
-- UPDATE emp SET sal = sal + 100 WHERE empno = 7499; -- блокирует строку B
-- затем попытка UPDATE emp SET sal = sal + 100 WHERE empno = 7369; -- ждёт строку A → взаимная блокировка
-- Итог: один сеанс получит ORA-00060 deadlock detected. Решение — единый порядок блокировок.

/*
Автоматические коммиты при DDL
*/
-- DDL выполняет неявный COMMIT ДО и ПОСЛЕ. Демонстрация:
INSERT INTO emp (empno, ename, deptno, sal) VALUES (10001, 'DDL_USER', 10, 1000);
CREATE TABLE t_ddl_demo (id NUMBER);
ROLLBACK; -- вставка выше уже зафиксирована (DDL сделал COMMIT)
-- Проверить:
SELECT * FROM emp WHERE empno = 10001; -- строка останется
DROP TABLE t_ddl_demo PURGE;

/*
PL/SQL: Функции и процедуры с IN/OUT параметрами
*/
-- Функция: возвращает годовой доход
CREATE OR REPLACE FUNCTION annual_income(p_monthly_sal IN NUMBER)
RETURN NUMBER AS
BEGIN
  RETURN p_monthly_sal * 12;
END;
/

-- Процедура: применяет raise и возвращает новое значение через OUT
CREATE OR REPLACE PROCEDURE apply_raise(
  p_empno   IN  NUMBER,
  p_percent IN  NUMBER,
  p_new_sal OUT NUMBER
) AS
BEGIN
  UPDATE emp SET sal = sal * (1 + p_percent/100)
  WHERE empno = p_empno
  RETURNING sal INTO p_new_sal;
END;
/

-- Вызов процедуры из анонимного блока
DECLARE
  v_new_sal NUMBER;
BEGIN
  apply_raise(7369, 5, v_new_sal);
  DBMS_OUTPUT.PUT_LINE('New SAL = ' || v_new_sal);
END;
/
