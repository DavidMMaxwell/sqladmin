/* INDEX: Index Analysis Procedure. 
   David Maxwell, December 2013
   Gives important statistics on database indexes.  Useful for 
   determining what indexes are required and if proper maintenance is 
   being done.  SQL 2005 and up.
*/

USE [master];
GO

IF (SELECT OBJECT_ID('sp_dm_IndexAnalysis')) IS NULL
BEGIN 
    EXEC ('CREATE PROCEDURE sp_dm_IndexAnalysis
            AS
            PRINT ''STUB VERSION - Replace with actual procedure.'';
            ')
END
GO

ALTER PROCEDURE sp_dm_IndexAnalysis
/***************************************************************
  Name: sp_dm_IndexAnalysis.sql
  Project/Ticket#: Administrative
  Date: December 2013
  Requester: Nobody. (Or everybody, depending on your view.)
  DBA: David M Maxwell
  Step: -- of --
  Server: Yours.
  Instructions: Performs analysis of indexes on a given database. 
    Includes fragmentation, usage statistics, and last update 
    date for stats.

  Specify the database name and level of detail required from the
  dm_db_index_physical_stats DMV. Options are LIMITED, SAMPLED 
  or DETAILED. Remember that the more detailed you get, the more
  resources the procedure will consume. 

  Also remember that this could take a large amount of time on a
  large database, with a large number of indexes. Not to mention
  a large amount of resources. Plan accordingly. You may want to
  consider running this only on the problem indexes, one at a time.

  Test Execution:

  EXEC sp_dm_IndexAnalysis
    @DBName = 'SQLAdmin',
	@Object = NULL, 
	@Index = NULL,
    @DetailLevel = 'LIMITED'
  GO

***************************************************************/
  @DBName sysname = NULL, /* Name of the database you want to analyze */
  @Table varchar(100) = NULL, /* Name of a table to analyze. NULL = all tables. */
  @Index varchar(150) = NULL, /* Name of an index to analyze. NULL = all indexes. */
  @DetailLevel varchar(8) =  'LIMITED' /* Level of detail required. */
AS

SET NOCOUNT ON;


DECLARE
  @dbid int, /* dbid is needed for the dmv query */
  @tableid int, /* table id for column listing */
  @indexid int, /* index id for column listing */
  @cols varchar(4000), /* holder for column list */
  @sqlcmd nvarchar(4000), /* Command holder. */
  @errormsg nvarchar(4000) /* Error message holder. */

SELECT @dbid = db_id(@DBName) /* get the database id from @DBName */

/* Create the table to hold the column information for each index. */
IF (SELECT OBJECT_ID('tempdb.dbo.#IndexColumns')) IS NOT NULL
DROP TABLE #IndexColumns

/* If the table name or index name has been specified in the 
   parameters, we want to make sure those objects exist, and
   also convert them to their object IDs, to head of any 
   SQL Injection silliness.
*/
/* LEFT OFF HERE */
IF (SELECT @Table) IS NOT NULL
BEGIN 
	SELECT @sqlcmd = N'
	SELECT [object_id] 
	FROM [' + db_name(@dbid) +'].sys.tables
	WHERE name = ''
	'

/* Now get the index column listing. */
SELECT TableName = T.Name, 
       IndexName = ISNULL(I.Name,'HEAP'),
       IndexColumns = CAST(NULL AS varchar(max))
INTO #IndexColumns
FROM   sys.tables T
INNER JOIN sys.indexes I
  ON T.[object_id] = I.[object_id]

/* Now that we have a list of tables and indexes, get the column 
   info for each one. 
*/

WHILE (SELECT COUNT(*) FROM #IndexColumns WHERE IndexColumns IS NULL) > 0
BEGIN
  SELECT TOP 1 @tname = TableName, @iname = IndexName 
  FROM #IndexColumns
  WHERE IndexColumns IS NULL
  
  SELECT @cols = '' /* need to start blank, but not NULL */
  
  SELECT  @cols = isnull(@cols + ', ', '') + C.name + '(' + Y.name + ')'
  FROM sys.tables T
  INNER JOIN sys.indexes I
    ON T.[object_id] = I.[object_id]
  INNER JOIN sys.index_columns IC
    ON T.[object_id] = IC.[object_id]
   AND I.[index_id] = IC.[index_id]
  INNER JOIN sys.columns C
    ON T.[object_id] = C.[object_id]
   AND IC.[column_id] = C.[column_id]
  INNER JOIN sys.types Y
    ON C.system_type_id = Y.system_type_id
  WHERE T.Name = @tname
    AND I.Name = @iname

  /* Need to chop off the leading comma in the column lists. */
  UPDATE #IndexColumns
  SET IndexColumns = SUBSTRING(@cols,3,LEN(@cols))
  WHERE TableName = @tname
    AND IndexName = @iname
    
END

/* Get the index information, including current fragmentation
   along with the list of columns in each index.
*/
SELECT 
  T.name AS TableName, 
  ISNULL(I.name,'HEAP') AS IndexName, 
  CASE I.is_unique  
    WHEN 1 THEN 'UNIQUE'
    ELSE 'NOT UNIQUE'
  END AS IsUnique,
  F.index_type_desc AS IndexType, 
  F.alloc_unit_type_desc AS AllocationType,
  F.page_count AS PgCount,
  F.record_count AS RecordCount,
  (F.page_count * 8) / 1024 AS SizeInMB,
  F.avg_fragmentation_in_percent AS PercentFragmentation,
  CONVERT(varchar(24),STATS_DATE(T.[Object_ID], I.index_id),120) AS StatsUpdated,
  S.user_seeks AS UserSeeks,
  S.user_scans AS UserScans,
  S.user_updates AS UserUpdates,
  S.user_lookups AS UserLookups,
  C.IndexColumns
FROM sys.tables T  
INNER JOIN sys.indexes I
  ON T.[object_id] = I.[object_id]
LEFT OUTER JOIN #IndexColumns C
  ON T.name = C.TableName
 AND I.name = C.IndexName
LEFT OUTER JOIN sys.dm_db_index_usage_stats S
  ON S.[object_id] = T.[object_id]
 AND S.[index_id] = I.[index_id]
LEFT OUTER JOIN sys.dm_db_index_physical_stats (
  @dbid, NULL, NULL, NULL, @DetailLevel ) F
  ON I.[object_id] = F.[object_id]
 AND I.index_id = F.index_id
WHERE F.database_id = @dbid
  AND T.type_desc = 'USER_TABLE'
ORDER BY T.name, I.name 
GO


