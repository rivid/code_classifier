SELECT * FROM `users` WHERE `id` = 1', 'select * from users where id = 1
SELECT * FROM `t1` WHERE `id` > (SELECT SUM(`a`) FROM `t2`)
SELECT * FROM `users` ORDER BY 1 ASC', 'SELECT * FROM users ORDER BY 1
SELECT * FROM `users` GROUP BY `name`
CREATE OR REPLACE FUNCTION foo(
	p_in1 VARCHAR
	, p_in2 INTEGER
) RETURNS INTEGER AS

  DECLARE
	v_foo INTEGER;  
  BEGIN
  	SELECT *
  	FROM foo
  	INTO v_foo;
  	RETURN v_foo.id;
  END;

CREATE OR REPLACE FUNCTION public.delete_data (
    p_tabelle VARCHAR
  , p_key VARCHAR
  , p_value INTEGER
) RETURNS INTEGER AS
$$
DECLARE
    p_retval                INTEGER;
    v_constraint            RECORD;
    v_count                 INTEGER;
    v_data                  RECORD;
    v_fieldname             VARCHAR;
    v_sql                   VARCHAR;
    v_key                   VARCHAR;
    v_value                 INTEGER;
BEGIN
    v_sql := 'SELECT COUNT(*) FROM ' || p_tabelle || ' WHERE ' || p_key || ' = ' || p_value;
    --RAISE NOTICE '%', v_sql;
    EXECUTE v_sql INTO v_count;
    IF v_count::integer != 0 THEN
        SELECT att.attname
            INTO v_key
            FROM pg_attribute att
                LEFT JOIN pg_constraint con ON con.conrelid = att.attrelid 
                    AND con.conkey[1] = att.attnum 
                    AND con.contype = 'p', pg_type typ, pg_class rel, pg_namespace ns
            WHERE att.attrelid = rel.oid
                AND att.attnum > 0 
                AND typ.oid = att.atttypid
                AND att.attisdropped = false
                AND rel.relname = p_tabelle
                AND con.conkey[1] = 1
                AND ns.oid = rel.relnamespace
                AND ns.nspname = 'public'
            ORDER BY att.attnum;
        v_sql := 'SELECT ' || v_key || ' AS id FROM ' || p_tabelle || ' WHERE ' || p_key || ' = ' || p_value;
        FOR v_data IN EXECUTE v_sql
        LOOP
            --RAISE NOTICE ' -> % %', p_tabelle, v_data.id;
            FOR v_constraint IN SELECT t.constraint_name
                                , t.constraint_type
                                , t.table_name
                                , c.column_name
                                FROM public.v_table_constraints t
                                    , public.v_constraint_columns c
                                WHERE t.constraint_name = c.constraint_name
                                    AND t.constraint_type = 'FOREIGN KEY'
                                    AND c.table_name = p_tabelle
                                    AND t.table_schema = 'public'
                                    AND c.table_schema = 'public'
            LOOP
                v_fieldname := substring(v_constraint.constraint_name from 1 for length(v_constraint.constraint_name) - length(v_constraint.column_name) - 1);
                IF (v_constraint.table_name = p_tabelle) AND (p_value = v_data.id) THEN
                    --RAISE NOTICE 'Skip (Selbstverweis)';
                    CONTINUE;
                ELSE
                    PERFORM delete_data(v_constraint.table_name::varchar, v_fieldname::varchar, v_data.id::integer);
                END IF;
            END LOOP;
        END LOOP;
        v_sql := 'DELETE FROM ' || p_tabelle || ' WHERE ' || p_key || ' = ' || p_value;
        --RAISE NOTICE '%', v_sql;
        EXECUTE v_sql;
        p_retval := 1;
    ELSE
        --RAISE NOTICE ' -> Keine Sätze gefunden';
        p_retval := 0;
    END IF;
    RETURN p_retval;
END;
$$
LANGUAGE plpgsql;
INSERT INTO table (column1, column2) VALUES("test ()", CURDATE())

INSERT INTO table (col_A,col_B,col_C) VALUES (1,2,3)
INSERT INTO table (col_A,col_B,col_C) VALUES (1,2,3), (4,5,6), (7,8,9)
UPDATE table SET column1 = "string ()", column2=5,column3=column4, column5 = CURDATE(), column6 = FUNCTION("string ()", column7) WHERE id = 5
INSERT INTO table (col_A, col_B, col_C) VALUES (1, 2, 3)

DELETE FROM table WHERE id = 5
DELETE FROM table1, table2 WHERE id = 5
UPDATE table1, table2 SET column = 1
UPDATE table SET column1 = "string ()", column2=5, column3=column4, column5 = CURDATE(), column6 = FUNCTION("string ()", column7) WHERE id = 5