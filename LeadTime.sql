DECLARE @LTS numeric(8,3)--Lead Time Standard
DECLARE @LS numeric(8,3) --Lead Time Standard Scale

SET @LTS=18 --18 days
SET @LS=CEILING(@LTS/10)

	
DECLARE @POTrack table 
(pohId nvarchar(14) ,ordDate nvarchar(8) ,suplId nvarchar(6) ,itemId nvarchar(24)
,totalOrderedQty INTEGER ,totalreceivedQty INTEGER ,price numeric(20,6)
, receivedDate nvarchar(8), receivedQty INTEGER)

INSERT @POTrack
SELECT HD.pohId,HD.ordDate,HD.suplId,HD.itemId,HD.totalOrdered ,HD.totalReceived ,HD.price, GH.tranDate AS receivedDate , GH.qty AS receivedQty
FROM
	(SELECT H.[pohId],H.[ordDate],H.[suplId],D.[itemId]
	  ,SUM(D.[ordered]) AS totalOrdered,SUM(D.[received]) AS totalReceived ,AVG(D.[price]) AS price
	FROM
		(SELECT [pohId]
				,[pohRev]
				--,[poStatus]
				,[suplId]
				--,[name]
				,[ordDate]
				--,[jobId]
				--,[locId]
		FROM [CVE].[dbo].[MIPOH]
		WHERE [poStatus] IN (1,2)
		AND [ordDate]>= GETDATE()-90
		AND LEFT(pohId,3) IN ('PMS')) AS H--'PMS' ONLY FOR APPLE and Samsung, no SALVAGE/EXCHANGE...
	INNER JOIN
		(SELECT[pohId]
				,[pohRev]
				,[podId]
				,[dType]
				,[dStatus]
				,[itemId]
				,[ordered]
				,[received]
				,[price]
		FROM [CVE].[dbo].[MIPOD]
		WHERE [dType]=0--INVENTORY
		AND [dStatus] IN(1,2)) AS D
	ON H.pohId =D.pohId
	AND H.pohRev= D.pohRev
	GROUP BY H.[pohId],H.[ordDate],H.[suplId],D.[itemId]) AS HD
INNER JOIN
	(SELECT [tranDate]
		  ,[type]
		  ,[itemId]
		  ,[revId]
		  ,[qty]
		  --,[jobId]
		  --,[locId]
		  --,[xvarSuplId]
		  ,[xvarPOId]
		  ,[xvarPORev]
	FROM [CVE].[dbo].[MILOGH]
	WHERE TYPE =12
	AND [tranDate]>= GETDATE()-90) AS GH
ON HD.pohId=GH.xvarPOId
AND HD.itemId=GH.itemId



SELECT LT.*
FROM
	(SELECT SI.suplId, SI.itemId, AVG(SI.poLeadTimeScore) AS leadTimeScore--, count(*) 
	FROM
		(SELECT leadScore.pohId, leadScore.suplId , leadScore.itemId, SUM(leadScore.leadTimeScoreofthisrecord) AS poLeadTimeScore
		FROM
			(SELECT PO.pohId, PO.ordDate, PO.suplId, PO.itemId, PO.totalOrderedQty, PO.totalreceivedQty,  PO.receivedDate, PO.receivedQty--PO.price,
				   ,CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) ) AS leadTime
				   ,CASE
						 WHEN (CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) )-@LTS)/@LS <= -5 THEN 5.0 *(CAST(PO.receivedQty AS NUMERIC(12,5))/CAST(PO.totalOrderedQty AS NUMERIC(12,5)))
						 WHEN (CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) )-@LTS)/@LS > -5 
						 AND  (CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) )-@LTS)/@LS <=10  THEN 
						 (10-ABS((CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) )-@LTS)/@LS)) *(CAST(PO.receivedQty AS NUMERIC(12,5))/CAST(PO.totalOrderedQty AS NUMERIC(12,5)))
						 WHEN (CONVERT( FLOAT,CONVERT(DATETIME,PO.receivedDate)-CONVERT(DATETIME,PO.ordDate) )-@LTS)/@LS >10   THEN 0
						 ELSE 9999999999
					END  AS leadTimeScoreofthisrecord
			FROM @POTrack AS PO
			WHERE NOT EXISTS --EXCLUDE  O.receivedQty<0, Because those items may be rejected..., it was received and then returned
				(SELECT *
				FROM
					(SELECT O.pohId,O.itemId
					FROM @POTrack AS O
					WHERE O.receivedQty<0) AS negQty
				WHERE PO.pohId=negQty.pohId
				AND PO.itemId=negQty.itemId )) AS leadScore
		GROUP BY leadScore.pohId, leadScore.suplId , leadScore.itemId) AS SI
	GROUP BY SI.suplId, SI.itemId) AS LT
INNER JOIN 
   (SELECT [itemId]
	FROM [CVE].[dbo].[MIITEM]
	WHERE [type] IN (0,2)
	AND [status]=0
	AND RIGHT(xdesc,5)='APPLE') AS ITEM--ONLY RIGHT(xdesc,5)='APPLE' PART
ON LT.itemId=ITEM.itemId





