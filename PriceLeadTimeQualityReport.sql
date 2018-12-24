-------------------------------------------price table
DECLARE @itemSupPri table
(suplId nvarchar(10),itemId nvarchar(20),price numeric (12,3))

DECLARE @price table
(itemId nvarchar(20),suplId nvarchar(10),priceScore numeric (12,3))


INSERT @itemSupPri
SELECT HDT.suplId, HDT.itemId, HDT.price
FROM
	(SELECT HD.*
	FROM
		(SELECT POH.suplId, POD.itemId, POH.ordDate,POD.price, ROW_NUMBER() OVER (PARTITION BY POH.suplId, POD.itemId ORDER BY POH.ordDate DESC) AS num
		FROM
			(SELECT [pohId]
				  ,[pohRev]
				  --,[poStatus]
				  ,[suplId]
				  ,[ordDate]
				  --,[jobId]
				  --,[locId]
			FROM [CVE].[dbo].[MIPOH]
			WHERE [poStatus] IN(1,2)
			AND [ordDate]>= GETDATE()-90
			AND LEFT(pohId,3) IN ('PMS')) AS POH--'PMS' ONLY FOR APPLE and Samsung, no SALVAGE/EXCHANGE...
		INNER JOIN
			(SELECT [pohId]
				  ,[pohRev]
				  ,[podId]
				  --,[dType]
				  --,[dStatus]
				  ,[jobId]
				  ,[locId]
				  ,[itemId]
				  --,[ordered]
				  --,[received]
				  ,[price]
			FROM [CVE].[dbo].[MIPOD]
			WHERE [dType]=0
			AND [dStatus] IN (1,2)) AS POD
		ON POH.pohId=POD.pohId
		AND POH.pohRev=POD.pohRev) AS HD
	WHERE HD.num=1) AS HDT
INNER JOIN
	(SELECT [itemId]
	FROM [CVE].[dbo].[MIITEM]
	WHERE [type] IN (0,2)
	AND [status]=0
	AND RIGHT(xdesc,5)='APPLE') AS ITEM--ONLY RIGHT(xdesc,5)='APPLE' PART
ON HDT.itemId=ITEM.itemId

-----------------------------insert data to price table
INSERT @price
SELECT isp.itemId
	  ,isp.suplId
	  --,isp.price
	  --,sp.standardPrice
	   ,CASE
			WHEN (sp.standardPrice/10)!=0 THEN CASE 
													WHEN 5- ((isp.price-sp.standardPrice)/(sp.standardPrice/10))<0  THEN 0
													WHEN 5- ((isp.price-sp.standardPrice)/(sp.standardPrice/10))>10 THEN 10
													ELSE 5- ((isp.price-sp.standardPrice)/(sp.standardPrice/10))
												END
			ELSE 0
		END  AS priceScore
FROM @itemSupPri AS isp
FULL JOIN
	(SELECT MM.itemId,(MM.minP+MM.maxP+MED.medP)/3 AS standardPrice--,MM.minP,MM.maxP, MED.medP
	FROM
		(SELECT minMax.itemId, MIN(minMax.price) AS minP , MAX(minMax.price) AS maxP
		FROM @itemSupPri AS minMax
		GROUP BY minMax.itemId) AS MM--get MIN MAX Price for each item
	FULL JOIN
		(SELECT MD.itemId ,AVG(MD.price) AS medP
		FROM
			(SELECT medData.itemId
					,medData.price
					,ROW_NUMBER() OVER(PARTITION BY medData.itemId ORDER BY medData.Price) AS rowNum, CAST(COUNT(*) OVER(PARTITION BY medData.itemId) AS FLOAT) AS count
			FROM @itemSupPri AS medData) AS MD
		WHERE MD.rowNum IN ( CAST((COUNT/2) AS FLOAT)+0.5 , CAST((COUNT/2) AS FLOAT), CAST((COUNT/2) AS FLOAT)+1 )
		GROUP BY MD.itemId) AS MED--get Medium Price for each item
	ON MM.itemId=MED.itemId) AS SP--get standard price
ON isp.itemId=SP.itemId
--------------------------PRICE table







-----------------------------lead time table
DECLARE @LTS numeric(8,3)--Lead Time Standard
DECLARE @LS numeric(8,3) --Lead Time Standard Scale
DECLARE @leadTime table
(suplId nvarchar(10),itemId nvarchar(20),leadTimeScore numeric (12,3))


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


-----------------insert data
INSERT @leadTime 
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

-----------------------------lead time table






-------------------Quality table

DECLARE @IPRate table
(itemId nvarchar(20) ,SuplId nvarchar(10),passRate numeric(10,5))

DECLARE @quality table
(itemId nvarchar(20) ,SuplId nvarchar(10),passRateScore numeric(10,5))


INSERT @IPRate
SELECT I.itemId
       ,I.xvarSuplId AS SuplId 
	   --,SUM(I.IQCQty) AS IQCQty 
	   --,SUM(IP.passQty) AS passQty
	   ,SUM(IP.passQty)/SUM(I.IQCQty) AS passRate
FROM
	(SELECT R.xvarSuplId, IQC.comment,IQC.itemId,IQC.IQCQty
	FROM
		(SELECT H.[itemId]
				,comment
				,[xvarSuplId]		
		FROM [CVE].[dbo].[MILOGH] AS H
		INNER JOIN [CVE].[dbo].[MIITEM] AS I
		ON H.itemId=I.itemId
		WHERE H.TYPE =12
		AND I.type IN(0,2)
		AND I.status=0
		AND H.[locId]='RCV'
		AND LEFT([comment],3)='RCV'
		AND [tranDate]>= GETDATE()-90) AS R
	INNER JOIN
		(SELECT I.comment,I.itemId,SUM(I.qty) AS IQCQty
		FROM
			(SELECT [tranDate]
					,[type]
					,[itemId]
					,CASE WHEN CHARINDEX('|',[comment])=0 THEN [comment]
						ELSE LEFT([comment],CHARINDEX('|',[comment])-1)
					 END AS comment
					,[qty]
					--,[jobId]
					--,[locId]
					--,[xvarToLoc]
			FROM [CVE].[dbo].[MILOGH]
			WHERE [locId]='RCV'
			AND [xvarToLoc]='IQC'
			AND TYPE =24
			AND [tranDate]>= GETDATE()-90) AS I
		GROUP BY I.comment,I.itemId) AS IQC
	ON R.comment=IQC.comment
	AND R.itemId=IQC.itemId) AS I
INNER JOIN
	(SELECT IQCP.comment, IQCP.itemId, SUM(QTY) AS passQty
	FROM
		(SELECT [tranDate]
				,[type]
				,[itemId]
				,[comment]
				,[qty]
				,[jobId]
				,[locId]
				,[xvarToLoc]
		FROM [CVE].[dbo].[MILOGH]
		WHERE TYPE =24
		AND [locId]='IQC'
		AND [xvarToLoc]='IQC_P'
		AND [tranDate]>= GETDATE()-90) AS IQCP
	GROUP BY IQCP.comment, IQCP.itemId) AS IP
ON I.comment=IP.comment
AND I.itemId=IP.itemId
GROUP BY I.xvarSuplId,I.itemId


--------------------insert data
INSERT @quality
SELECT PRS.*
FROM
	(SELECT IR.itemId, IR.SuplId--, IR.passRate, SP.standardPR
		   ,CASE 
				WHEN (IR.passRate>SP.standardPR)  THEN  CASE 
															 WHEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) )<=10 THEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) )
															 WHEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) )> 10 THEN 10
															 ELSE 9999999--MEANS UNREASONAL VALUE HAPPENS
														 END
				WHEN (IR.passRate<SP.standardPR)  THEN  CASE
															 WHEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) )>=0  THEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) )
															 WHEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) )< 0  THEN 0
															 ELSE 9999999
														 END
				WHEN (IR.passRate=SP.standardPR)  THEN 5
				ELSE 9999999 
			END AS passRateScore
			--,CASE-- WHEN EXTREME VALUE HAPPENS, THIS WOULD BE VERY SENSITIVE
			--     WHEN SP.standardPR>0.5 AND SP.standardPR<1   THEN CASE --SP.standardPR<1 AVOID DENOMITOR TO BE 0
			--									                       WHEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) ) >=0 THEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) )
			--														   WHEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) ) <0  THEN 0
			--									                       ELSE 9999999999
			--								                       END
			--	 WHEN SP.standardPR<0.5 AND SP.standardPR>0   THEN CASE  --SP.standardPR>0 AVOID DENOMITOR TO BE 0
			--														   WHEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) ) <=10 THEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) )
			--														   WHEN 5+( (IR.passRate-SP.standardPR) / ((SP.standardPR-0)/5) ) > 10 THEN 10
			--													       ELSE 9999999999
			--								                       END
			--	 WHEN SP.standardPR=0.5 THEN 5+( (IR.passRate-SP.standardPR) / ((1-SP.standardPR)/5) )
			--	 WHEN SP.standardPR=1   THEN 5  --WHEN SP.standardPR=0 --MEANS MIN MAX MEDIUN ALL 1, SO EVERY RECORDS ARE 1
			--	 WHEN SP.standardPR=0   THEN 0  --WHEN SP.standardPR=0 --MEANS MIN MAX MEDIUN ALL 0, SO EVERY RECORDS ARE 0
			--	 ELSE 99999999999999999
			-- END
	FROM @IPRate AS IR
	FULL JOIN
		(SELECT MM.itemId,(MM.minPR+MM.maxPR+ME.medPR)/3 AS standardPR--,MM.minPR,MM.maxPR, ME.medPR
		FROM
			(SELECT DISTINCT minMax.itemId
				  ,MIN(minMax.passRate) OVER(PARTITION BY minMax.itemId) AS minPR
				  ,MAX(minMax.passRate) OVER(PARTITION BY minMax.itemId) AS maxPR
				  --,minMax.passRate,minMax.SuplId
			FROM @IPRate AS minMax) AS MM--get MIN/MAX pass rate
		FULL JOIN
			(SELECT DISTINCT MD.itemId, AVG(MD.passRate) OVER(PARTITION BY MD.itemId ) AS medPR--,MD.SuplId, MD.rowNum, MD.COUNT
			FROM
				(SELECT med.itemId,med.SuplId,med.passRate
					  ,CAST(ROW_NUMBER() OVER(PARTITION BY med.itemId ORDER BY med.passRate) AS NUMERIC(5,2)) AS rowNum
					  ,CAST(COUNT(*) OVER(PARTITION BY med.itemId) AS NUMERIC(5,2)) AS COUNT
				FROM @IPRate AS med) AS MD
			WHERE MD.rowNum IN ( (MD.COUNT/2)+0.5,(MD.COUNT/2),(MD.COUNT/2)+1) ) AS Me--get Medium pass rate
		ON MM.itemId=ME.itemId) AS SP
	ON IR.itemId=SP.itemId) AS PRS
INNER JOIN 
   (SELECT [itemId]
	FROM [CVE].[dbo].[MIITEM]
	WHERE [type] IN (0,2)
	AND [status]=0
	AND RIGHT(xdesc,5)='APPLE') AS ITEM--ONLY RIGHT(xdesc,5)='APPLE' PART
ON PRS.itemId=ITEM.itemId

-------------------Quality table



----------Join 3 table price/lead time/quality
SELECT PT.*, Q.passRateScore, (PT.priceScore+PT.leadTimeScore+Q.passRateScore)/3 AS totalScore
FROM
	(SELECT P.itemId,P.suplId,P.priceScore,L.leadTimeScore
	FROM @price AS P
	INNER JOIN @leadTime AS L
	ON P.itemId=L.itemId
	AND P.suplId=L.suplId) AS PT
INNER JOIN @quality AS Q
ON PT.itemId=Q.itemId
AND PT.suplId=Q.SuplId
----------Join 3 table


----------Join 2 table price/lead time
SELECT P.itemId,P.suplId,P.priceScore,L.leadTimeScore,(P.priceScore+L.leadTimeScore)/2 AS totalScore
FROM @price AS P
INNER JOIN @leadTime AS L
ON P.itemId=L.itemId
AND P.suplId=L.suplId
----------Join 2 table







