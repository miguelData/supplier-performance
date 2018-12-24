DECLARE @IPRate table
(itemId nvarchar(20) ,SuplId nvarchar(10),passRate numeric(10,5))


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