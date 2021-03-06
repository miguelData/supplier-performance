/****** Script for SelectTopNRows command from SSMS  ******/

DECLARE @itemSupPri table
(suplId nvarchar(10),itemId nvarchar(20),price numeric (12,3))


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





