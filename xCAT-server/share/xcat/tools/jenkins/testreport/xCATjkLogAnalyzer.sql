-- MySQL dump 10.14  Distrib 5.5.47-MariaDB, for Linux (ppc64)
--
-- Host: localhost    Database: xCATjkLogAnalyzer
-- ------------------------------------------------------
-- Server version	5.5.47-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `ArchDict`
--

DROP TABLE IF EXISTS `ArchDict`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ArchDict` (
  `ArchId` int(11) NOT NULL AUTO_INCREMENT,
  `ArchName` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`ArchId`),
  UNIQUE KEY `ArchName` (`ArchName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `FailedTestCasesTopList`
--

DROP TABLE IF EXISTS `FailedTestCasesTopList`;
/*!50001 DROP VIEW IF EXISTS `FailedTestCasesTopList`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `FailedTestCasesTopList` (
  `Test case` tinyint NOT NULL,
  `Arch` tinyint NOT NULL,
  `OS` tinyint NOT NULL,
  `Last seven days` tinyint NOT NULL,
  `Last thirty days` tinyint NOT NULL,
  `Last ninety days` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `LatestDailyReport`
--

DROP TABLE IF EXISTS `LatestDailyReport`;
/*!50001 DROP VIEW IF EXISTS `LatestDailyReport`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `LatestDailyReport` (
  `Title` tinyint NOT NULL,
  `Arch` tinyint NOT NULL,
  `OS` tinyint NOT NULL,
  `Duration` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL,
  `Pass rate` tinyint NOT NULL,
  `Failed test cases` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `NinetyDayFailed`
--

DROP TABLE IF EXISTS `NinetyDayFailed`;
/*!50001 DROP VIEW IF EXISTS `NinetyDayFailed`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `NinetyDayFailed` (
  `TestCaseId` tinyint NOT NULL,
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Failed` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `NinetyDayLookBack`
--

DROP TABLE IF EXISTS `NinetyDayLookBack`;
/*!50001 DROP VIEW IF EXISTS `NinetyDayLookBack`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `NinetyDayLookBack` (
  `Arch` tinyint NOT NULL,
  `OS` tinyint NOT NULL,
  `Test runs` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL,
  `Pass rate` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `NinetyDayReport`
--

DROP TABLE IF EXISTS `NinetyDayReport`;
/*!50001 DROP VIEW IF EXISTS `NinetyDayReport`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `NinetyDayReport` (
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `OSDict`
--

DROP TABLE IF EXISTS `OSDict`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `OSDict` (
  `OSId` int(11) NOT NULL AUTO_INCREMENT,
  `OSName` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`OSId`),
  UNIQUE KEY `OSName` (`OSName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ResultDict`
--

DROP TABLE IF EXISTS `ResultDict`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ResultDict` (
  `ResultId` int(11) NOT NULL AUTO_INCREMENT,
  `ResultName` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`ResultId`),
  UNIQUE KEY `ResultName` (`ResultName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `SevenDayFailed`
--

DROP TABLE IF EXISTS `SevenDayFailed`;
/*!50001 DROP VIEW IF EXISTS `SevenDayFailed`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `SevenDayFailed` (
  `TestCaseId` tinyint NOT NULL,
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Failed` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `SevenDayLookBack`
--

DROP TABLE IF EXISTS `SevenDayLookBack`;
/*!50001 DROP VIEW IF EXISTS `SevenDayLookBack`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `SevenDayLookBack` (
  `Arch` tinyint NOT NULL,
  `OS` tinyint NOT NULL,
  `Test runs` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL,
  `Pass rate` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `SevenDayReport`
--

DROP TABLE IF EXISTS `SevenDayReport`;
/*!50001 DROP VIEW IF EXISTS `SevenDayReport`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `SevenDayReport` (
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `TestCase`
--

DROP TABLE IF EXISTS `TestCase`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TestCase` (
  `TestCaseId` int(11) NOT NULL AUTO_INCREMENT,
  `TestCaseName` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `Memo` text NOT NULL,
  PRIMARY KEY (`TestCaseId`),
  UNIQUE KEY `TestCaseName` (`TestCaseName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TestResult`
--

DROP TABLE IF EXISTS `TestResult`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TestResult` (
  `TestRunId` int(11) NOT NULL,
  `TestCaseId` int(11) NOT NULL,
  `ResultId` int(11) NOT NULL,
  `DurationTime` int(11) NOT NULL,
  PRIMARY KEY (`TestRunId`,`TestCaseId`),
  KEY `Result` (`ResultId`),
  KEY `TestCaseId` (`TestCaseId`),
  CONSTRAINT `ResutId` FOREIGN KEY (`ResultId`) REFERENCES `ResultDict` (`ResultId`),
  CONSTRAINT `TestCaseId` FOREIGN KEY (`TestCaseId`) REFERENCES `TestCase` (`TestCaseId`),
  CONSTRAINT `TestRunId` FOREIGN KEY (`TestRunId`) REFERENCES `TestRun` (`TestRunId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `TestRun`
--

DROP TABLE IF EXISTS `TestRun`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `TestRun` (
  `TestRunId` int(11) NOT NULL AUTO_INCREMENT,
  `TestRunName` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `StartTime` datetime NOT NULL,
  `EndTime` datetime NOT NULL,
  `ArchId` int(11) NOT NULL,
  `OSId` int(11) NOT NULL,
  `xCATgitCommit` varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `Memo` text NOT NULL,
  PRIMARY KEY (`TestRunId`),
  UNIQUE KEY `TestRunName` (`TestRunName`),
  KEY `ArchId` (`ArchId`),
  KEY `OSId` (`OSId`),
  CONSTRAINT `ArchId` FOREIGN KEY (`ArchId`) REFERENCES `ArchDict` (`ArchId`),
  CONSTRAINT `OSId` FOREIGN KEY (`OSId`) REFERENCES `OSDict` (`OSId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Temporary table structure for view `ThirtyDayFailed`
--

DROP TABLE IF EXISTS `ThirtyDayFailed`;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayFailed`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `ThirtyDayFailed` (
  `TestCaseId` tinyint NOT NULL,
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Failed` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `ThirtyDayLookBack`
--

DROP TABLE IF EXISTS `ThirtyDayLookBack`;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayLookBack`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `ThirtyDayLookBack` (
  `Arch` tinyint NOT NULL,
  `OS` tinyint NOT NULL,
  `Test runs` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL,
  `Pass rate` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `ThirtyDayReport`
--

DROP TABLE IF EXISTS `ThirtyDayReport`;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayReport`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `ThirtyDayReport` (
  `ArchId` tinyint NOT NULL,
  `OSId` tinyint NOT NULL,
  `Passed` tinyint NOT NULL,
  `Failed` tinyint NOT NULL,
  `No run` tinyint NOT NULL,
  `Subtotal` tinyint NOT NULL
) ENGINE=MyISAM */;
SET character_set_client = @saved_cs_client;

--
-- Final view structure for view `FailedTestCasesTopList`
--

/*!50001 DROP TABLE IF EXISTS `FailedTestCasesTopList`*/;
/*!50001 DROP VIEW IF EXISTS `FailedTestCasesTopList`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `FailedTestCasesTopList` AS select `TestCase`.`TestCaseName` AS `Test case`,`ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,ifnull(`SevenDayFailed`.`Failed`,0) AS `Last seven days`,ifnull(`ThirtyDayFailed`.`Failed`,0) AS `Last thirty days`,`NinetyDayFailed`.`Failed` AS `Last ninety days` from (((((`NinetyDayFailed` left join `SevenDayFailed` on(((`NinetyDayFailed`.`TestCaseId` = `SevenDayFailed`.`TestCaseId`) and (`NinetyDayFailed`.`ArchId` = `SevenDayFailed`.`ArchId`) and (`NinetyDayFailed`.`OSId` = `SevenDayFailed`.`OSId`)))) left join `ThirtyDayFailed` on(((`NinetyDayFailed`.`TestCaseId` = `ThirtyDayFailed`.`TestCaseId`) and (`NinetyDayFailed`.`ArchId` = `ThirtyDayFailed`.`ArchId`) and (`NinetyDayFailed`.`OSId` = `ThirtyDayFailed`.`OSId`)))) left join `TestCase` on((`NinetyDayFailed`.`TestCaseId` = `TestCase`.`TestCaseId`))) left join `ArchDict` on((`NinetyDayFailed`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`NinetyDayFailed`.`OSId` = `OSDict`.`OSId`))) order by ifnull(`SevenDayFailed`.`Failed`,0) desc,ifnull(`ThirtyDayFailed`.`Failed`,0) desc,`NinetyDayFailed`.`Failed` desc,`NinetyDayFailed`.`OSId` desc,`NinetyDayFailed`.`ArchId` desc */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `LatestDailyReport`
--

/*!50001 DROP TABLE IF EXISTS `LatestDailyReport`*/;
/*!50001 DROP VIEW IF EXISTS `LatestDailyReport`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `LatestDailyReport` AS select `TestRun`.`TestRunName` AS `Title`,`ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,timediff(`TestRun`.`EndTime`,`TestRun`.`StartTime`) AS `Duration`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) AS `Passed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'No run')))) AS `No run`,(select count(0) from `TestResult` where (`TestResult`.`TestRunId` = `TestRun`.`TestRunId`)) AS `Subtotal`,ifnull(concat(round((((select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) / ((select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) + (select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))))) * 100),2),'%'),'N/A') AS `Pass rate`,(select ifnull(group_concat(`TestCase`.`TestCaseName` separator ' '),'') from (`TestResult` left join `TestCase` on((`TestResult`.`TestCaseId` = `TestCase`.`TestCaseId`))) where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed test cases` from ((`TestRun` left join `ArchDict` on((`TestRun`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`TestRun`.`OSId` = `OSDict`.`OSId`))) where `TestRun`.`TestRunId` in (select max(`TestRun`.`TestRunId`) AS `TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 2 day)) group by `TestRun`.`ArchId`,`TestRun`.`OSId` order by max(`TestRun`.`TestRunId`)) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `NinetyDayFailed`
--

/*!50001 DROP TABLE IF EXISTS `NinetyDayFailed`*/;
/*!50001 DROP VIEW IF EXISTS `NinetyDayFailed`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `NinetyDayFailed` AS select `TestResult`.`TestCaseId` AS `TestCaseId`,`TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,count(0) AS `Failed` from (`TestResult` left join `TestRun` on((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`))) where (`TestResult`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 90 day))) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed'))) group by `TestResult`.`TestCaseId`,`TestRun`.`ArchId`,`TestRun`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `NinetyDayLookBack`
--

/*!50001 DROP TABLE IF EXISTS `NinetyDayLookBack`*/;
/*!50001 DROP VIEW IF EXISTS `NinetyDayLookBack`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `NinetyDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`NinetyDayReport`.`Passed`) AS `Passed`,sum(`NinetyDayReport`.`Failed`) AS `Failed`,sum(`NinetyDayReport`.`No run`) AS `No run`,sum(`NinetyDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`NinetyDayReport`.`Passed`) / (sum(`NinetyDayReport`.`Passed`) + sum(`NinetyDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`NinetyDayReport` left join `ArchDict` on((`NinetyDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`NinetyDayReport`.`OSId` = `OSDict`.`OSId`))) group by `NinetyDayReport`.`ArchId`,`NinetyDayReport`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `NinetyDayReport`
--

/*!50001 DROP TABLE IF EXISTS `NinetyDayReport`*/;
/*!50001 DROP VIEW IF EXISTS `NinetyDayReport`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `NinetyDayReport` AS select `TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) AS `Passed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'No run')))) AS `No run`,(select count(0) from `TestResult` where (`TestResult`.`TestRunId` = `TestRun`.`TestRunId`)) AS `Subtotal` from `TestRun` where `TestRun`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 90 day))) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `SevenDayFailed`
--

/*!50001 DROP TABLE IF EXISTS `SevenDayFailed`*/;
/*!50001 DROP VIEW IF EXISTS `SevenDayFailed`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `SevenDayFailed` AS select `TestResult`.`TestCaseId` AS `TestCaseId`,`TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,count(0) AS `Failed` from (`TestResult` left join `TestRun` on((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`))) where (`TestResult`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 7 day))) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed'))) group by `TestResult`.`TestCaseId`,`TestRun`.`ArchId`,`TestRun`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `SevenDayLookBack`
--

/*!50001 DROP TABLE IF EXISTS `SevenDayLookBack`*/;
/*!50001 DROP VIEW IF EXISTS `SevenDayLookBack`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `SevenDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`SevenDayReport`.`Passed`) AS `Passed`,sum(`SevenDayReport`.`Failed`) AS `Failed`,sum(`SevenDayReport`.`No run`) AS `No run`,sum(`SevenDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`SevenDayReport`.`Passed`) / (sum(`SevenDayReport`.`Passed`) + sum(`SevenDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`SevenDayReport` left join `ArchDict` on((`SevenDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`SevenDayReport`.`OSId` = `OSDict`.`OSId`))) group by `SevenDayReport`.`ArchId`,`SevenDayReport`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `SevenDayReport`
--

/*!50001 DROP TABLE IF EXISTS `SevenDayReport`*/;
/*!50001 DROP VIEW IF EXISTS `SevenDayReport`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `SevenDayReport` AS select `TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) AS `Passed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'No run')))) AS `No run`,(select count(0) from `TestResult` where (`TestResult`.`TestRunId` = `TestRun`.`TestRunId`)) AS `Subtotal` from `TestRun` where `TestRun`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 7 day))) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `ThirtyDayFailed`
--

/*!50001 DROP TABLE IF EXISTS `ThirtyDayFailed`*/;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayFailed`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `ThirtyDayFailed` AS select `TestResult`.`TestCaseId` AS `TestCaseId`,`TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,count(0) AS `Failed` from (`TestResult` left join `TestRun` on((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`))) where (`TestResult`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 30 day))) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed'))) group by `TestResult`.`TestCaseId`,`TestRun`.`ArchId`,`TestRun`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `ThirtyDayLookBack`
--

/*!50001 DROP TABLE IF EXISTS `ThirtyDayLookBack`*/;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayLookBack`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `ThirtyDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`ThirtyDayReport`.`Passed`) AS `Passed`,sum(`ThirtyDayReport`.`Failed`) AS `Failed`,sum(`ThirtyDayReport`.`No run`) AS `No run`,sum(`ThirtyDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`ThirtyDayReport`.`Passed`) / (sum(`ThirtyDayReport`.`Passed`) + sum(`ThirtyDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`ThirtyDayReport` left join `ArchDict` on((`ThirtyDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`ThirtyDayReport`.`OSId` = `OSDict`.`OSId`))) group by `ThirtyDayReport`.`ArchId`,`ThirtyDayReport`.`OSId` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `ThirtyDayReport`
--

/*!50001 DROP TABLE IF EXISTS `ThirtyDayReport`*/;
/*!50001 DROP VIEW IF EXISTS `ThirtyDayReport`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `ThirtyDayReport` AS select `TestRun`.`ArchId` AS `ArchId`,`TestRun`.`OSId` AS `OSId`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) AS `Passed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'No run')))) AS `No run`,(select count(0) from `TestResult` where (`TestResult`.`TestRunId` = `TestRun`.`TestRunId`)) AS `Subtotal` from `TestRun` where `TestRun`.`TestRunId` in (select `TestRun`.`TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 30 day))) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2016-06-29  4:52:47
