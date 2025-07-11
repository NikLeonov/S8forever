/*
ОГЛАВЛЕНИЕ: 
Пример использования Common Table Expressions (WITH ... AS) и LEFT JOIN. 
Создание view и materialized view для средней зарплаты по отделу из запроса выше.
Пример derived table (подзапрос во FROM)
Создание индекса
Создание hash-индекса 
пример согласованного отката двух изменений
пример согласованного коммита двух изменений
Пример отката до изменений до точки SAVEPOINT, и коммита предыдущих
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

