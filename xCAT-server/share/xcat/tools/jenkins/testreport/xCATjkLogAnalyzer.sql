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
-- Temporary table structure for view `LatestDailyMailReportSubject`
--

DROP TABLE IF EXISTS `LatestDailyMailReportSubject`;
/*!50001 DROP VIEW IF EXISTS `LatestDailyMailReportSubject`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
/*!50001 CREATE TABLE `LatestDailyMailReportSubject` (
  `Subject` tinyint NOT NULL
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
-- Dumping routines for database 'xCATjkLogAnalyzer'
--
/*!50003 DROP PROCEDURE IF EXISTS `CreateLatestDailyMailReport` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8 */ ;
/*!50003 SET character_set_results = utf8 */ ;
/*!50003 SET collation_connection  = utf8_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = '' */ ;
DELIMITER ;;
CREATE DEFINER=`root`@`localhost` PROCEDURE `CreateLatestDailyMailReport`()
BEGIN
SET group_concat_max_len := @@max_allowed_packet;
SELECT CONCAT(
'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">', "\n",
'<html xmlns="http://www.w3.org/1999/xhtml">', "\n",
'<head>', "\n",
'<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />', "\n",
'<meta name="viewpoint" content="width=device-width, initial-scale=1.0" />', "\n",
'<title>xCAT Jenkins Test Report</title>', "\n",
'</head>', "\n",
'<body style="font-weight: 500; font-size: 10.5pt; font-family: Helvetica, Arial, sans-serif; text-align: center;">', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; margin: auto; text-align: left; width: 680px;">', "\n",
'<tr style="vertical-align: baseline;">', "\n",
'<td style="padding: 2px 3px; vertical-align: top; width: 540px;"><p style="font-weight: 900; font-size: 16pt;">xCAT Jenkins Test Report</p></td>', "\n",
'<td style="padding: 2px 3px; text-align: right"><img src="data:image/png;base64,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" alt="xCAT Logo" title="xCAT Logo" style="border-style: none; border-width: 0;" width="120" height="90" /></td>', "\n",
'</tr>', "\n",
'</table>', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;"></p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px">Duration</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>', "\n",
'</tr>', "\n",
LatestDailyReportContents.HTML,
LatestDailyReportSummary.HTML,
'</table>', "\n",
'<hr style="background-color: #cccccc; border-width: 0; box-shadow: 1px 2px 3px #cccccc; height: 1px; width: 680px;" />', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;">Failed Test Cases</p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px;">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Failed test cases</th>', "\n",
'</tr>', "\n",
FailedTestCasesReport.HTML,
'</table>', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;">Seven-day Look Back</p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>', "\n",
'</tr>', "\n",
SevenDayLookBackContents.HTML,
SevenDayLookBackSummary.HTML,
'</table>', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;">Thirty-day Look Back</p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>', "\n",
'</tr>', "\n",
ThirtyDayLookBackContents.HTML,
ThirtyDayLookBackSummary.HTML,
'</table>', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;">Ninety-day Look Back</p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 80px;">Test runs</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Passed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Failed</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">No run</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 75px;">Subtotal</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Pass rate</th>', "\n",
'</tr>', "\n",
NinetyDayLookBackContents.HTML,
NinetyDayLookBackSummary.HTML,
'</table>', "\n",
'<p style="font-size: 12pt; font-weight: 700; text-align: center;">Top 50 Failed Test Cases</p>', "\n",
'<table style="border-collapse: collapse; border-style: none; border-width: 0; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #003366; color: #ffffff; font-weight: 700; text-align: center; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 40px;">Rank</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Test case</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 60px">Arch</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 100px;">OS</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 7 days</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 30 days</th>', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; width: 50px;">Last 90 days</th>', "\n",
'</tr>', "\n",
TopFiftyFailedTestCases.HTML,
'</table>', "\n",
'<hr style="background-color: #cccccc; border-width: 0; box-shadow: 1px 2px 3px #cccccc; height: 1px; width: 680px;" />', "\n",
'<table style="border-collapse: collapse; border-color: #666666; border-style: solid; border-width: 1px; box-shadow: 1px 2px 3px #cccccc; text-align: left; margin: auto; width: 680px;">', "\n",
'<tr style="background-color: #e0e0e0; vertical-align: baseline;">', "\n",
'<td style="padding: 4px 5px; vertical-align: bottom;"><p style="font-size: 9pt;"><sup>&#x273b;</sup>This email has been sent to you by xCAT Jenkins Mail Bot.<br />', "\n",
'<sup>&#x2020;</sup>This email was sent from a notification-only address that cannot accept incoming email. Please do not reply to this message. If you have received this email in error, please delete it.<br />', "\n",
'<sup>&#x2021;</sup>All the times shown in this test report are the local times of the testing environment.</p>', "\n",
'<p style="font-size: 9pt;">',
NOW(), ' ', REPLACE(CONCAT('+', TIME_FORMAT(TIMEDIFF(NOW(), UTC_TIMESTAMP), '%H%i')), '+-', '-'),
'</p></td>', "\n",
'</tr>', "\n",
'</table>', "\n",
'</body>', "\n",
'</html>'
) AS HTML
FROM (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#e0e0e0', @color := '#a0d0ff', @color := '#e0e0e0'),
'; vertical-align: baseline;" title="', Title, '">', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n"
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Duration, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Passed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Failed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`No run`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Subtotal, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Pass rate`, '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM LatestDailyReport,
( SELECT @color := '' ) AS tmp00
) AS tmp10
) AS LatestDailyReportContents, (
SELECT CONCAT(
'<tr style="background-color: #cccccc; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Total</th>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">-</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SEC_TO_TIME(SUM(TIME_TO_SEC(Duration))), 'N/A'), '</td>', "\n"
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Passed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Failed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`No run`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Subtotal), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A'), '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM LatestDailyReport
) AS LatestDailyReportSummary, (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#e0e0e0', @color := '#a0d0ff', @color := '#e0e0e0'),
'; vertical-align: baseline;" title="', Title, '">', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n",
'<td style="background-color: ',
IF (@color = '#e0e0e0', '#f0f0f0', '#d0e8ff'),
'; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
`Failed test cases`, '</td>', "\n",
'</tr>' , "\n"
) AS HTML
FROM LatestDailyReport,
( SELECT @color := '' ) AS tmp00
) AS tmp10
) AS FailedTestCasesReport, (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#e0e0e0', @color := '#a0d0ff', @color := '#e0e0e0'),
'; vertical-align: baseline;">', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Test runs`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Passed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Failed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`No run`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Subtotal, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Pass rate`, '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM SevenDayLookBack,
( SELECT @color := '' ) AS tmp00
) AS tmp10
) AS SevenDayLookBackContents, (
SELECT CONCAT(
'<tr style="background-color: #cccccc; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Total</th>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">-</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`Test runs`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Passed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Failed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`No run`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Subtotal), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A'), '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM SevenDayLookBack
) AS SevenDayLookBackSummary, (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#e0e0e0', @color := '#a0d0ff', @color := '#e0e0e0'),
'; vertical-align: baseline;">', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Test runs`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Passed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Failed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`No run`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Subtotal, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Pass rate`, '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM ThirtyDayLookBack,
( SELECT @color := '' ) AS tmp00
) AS tmp10
) AS ThirtyDayLookBackContents, (
SELECT CONCAT(
'<tr style="background-color: #cccccc; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Total</th>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">-</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`Test runs`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Passed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Failed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`No run`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Subtotal), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A'), '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM ThirtyDayLookBack
) AS ThirtyDayLookBackSummary, (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#e0e0e0', @color := '#a0d0ff', @color := '#e0e0e0'),
'; vertical-align: baseline;">', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Test runs`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Passed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Failed, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`No run`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
Subtotal, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Pass rate`, '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM NinetyDayLookBack,
( SELECT @color := '' ) AS tmp00
) AS tmp10
) AS NinetyDayLookBackContents, (
SELECT CONCAT(
'<tr style="background-color: #cccccc; vertical-align: baseline;">', "\n",
'<th style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">Total</th>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">-</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`Test runs`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Passed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Failed), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(`No run`), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(SUM(Subtotal), 'N/A'), '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
IFNULL(CONCAT(ROUND(SUM(Passed) / (SUM(Passed) + SUM(Failed)) * 100, 2), '%'), 'N/A'), '</td>', "\n",
'</tr>', "\n"
) AS HTML
FROM NinetyDayLookBack
) AS NinetyDayLookBackSummary, (
SELECT IFNULL(GROUP_CONCAT(HTML SEPARATOR ''), '') AS HTML
FROM (
SELECT CONCAT(
'<tr style="background-color: ',
IF (@color = '#f0f0f0', @color := '#d0e8ff', @color := '#f0f0f0'),
'; vertical-align: baseline;\">', "\n",
'<td style="background-color: ',
IF (@color = '#f0f0f0', '#e0e0e0', '#a0d0ff'),
'; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;\">',
@rank := @rank + 1, '</td>', "\n",
'<td style="background-color: ',
IF (@color = '#f0f0f0', '#e0e0e0', '#a0d0ff'),
'; border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
`Test case`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
Arch, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px;">',
OS, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Last seven days`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Last thirty days`, '</td>', "\n",
'<td style="border-color: #666666; border-style: solid; border-width: 1px; padding: 2px 3px; text-align: right;">',
`Last ninety days`, '</td>', "\n",
'</tr>', "\n"
) AS HTML FROM (
SELECT `Test case`, Arch, OS, `Last seven days`, `Last thirty days`, `Last ninety days`
FROM FailedTestCasesTopList LIMIT 50
) AS TopFifty,
( SELECT @color := '' ) AS tmp00,
( SELECT @rank := 0 ) AS tmp09
) AS tmp10
) AS TopFiftyFailedTestCases;
END ;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

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
/*!50001 VIEW `FailedTestCasesTopList` AS select `TestCase`.`TestCaseName` AS `Test case`,`ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,ifnull(`SevenDayFailed`.`Failed`,0) AS `Last seven days`,ifnull(`ThirtyDayFailed`.`Failed`,0) AS `Last thirty days`,`NinetyDayFailed`.`Failed` AS `Last ninety days` from (((((`NinetyDayFailed` left join `SevenDayFailed` on(((`NinetyDayFailed`.`TestCaseId` = `SevenDayFailed`.`TestCaseId`) and (`NinetyDayFailed`.`ArchId` = `SevenDayFailed`.`ArchId`) and (`NinetyDayFailed`.`OSId` = `SevenDayFailed`.`OSId`)))) left join `ThirtyDayFailed` on(((`NinetyDayFailed`.`TestCaseId` = `ThirtyDayFailed`.`TestCaseId`) and (`NinetyDayFailed`.`ArchId` = `ThirtyDayFailed`.`ArchId`) and (`NinetyDayFailed`.`OSId` = `ThirtyDayFailed`.`OSId`)))) left join `TestCase` on((`NinetyDayFailed`.`TestCaseId` = `TestCase`.`TestCaseId`))) left join `ArchDict` on((`NinetyDayFailed`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`NinetyDayFailed`.`OSId` = `OSDict`.`OSId`))) order by ifnull(`SevenDayFailed`.`Failed`,0) desc,ifnull(`ThirtyDayFailed`.`Failed`,0) desc,`NinetyDayFailed`.`Failed` desc,`OSDict`.`OSName`,`ArchDict`.`ArchName`,`TestCase`.`TestCaseName` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `LatestDailyMailReportSubject`
--

/*!50001 DROP TABLE IF EXISTS `LatestDailyMailReportSubject`*/;
/*!50001 DROP VIEW IF EXISTS `LatestDailyMailReportSubject`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8 */;
/*!50001 SET character_set_results     = utf8 */;
/*!50001 SET collation_connection      = utf8_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `LatestDailyMailReportSubject` AS select concat('[xCAT Jenkins] ','Passed: ',ifnull(sum(`LatestDailyReport`.`Passed`),'N/A'),' Failed: ',ifnull(sum(`LatestDailyReport`.`Failed`),'N/A'),' No run: ',ifnull(sum(`LatestDailyReport`.`No run`),'N/A')) AS `Subject` from `LatestDailyReport` */;
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
/*!50001 VIEW `LatestDailyReport` AS select `TestRun`.`TestRunName` AS `Title`,`ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,timediff(`TestRun`.`EndTime`,`TestRun`.`StartTime`) AS `Duration`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) AS `Passed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed`,(select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'No run')))) AS `No run`,(select count(0) from `TestResult` where (`TestResult`.`TestRunId` = `TestRun`.`TestRunId`)) AS `Subtotal`,ifnull(concat(round((((select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) / ((select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Passed')))) + (select count(0) from `TestResult` where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))))) * 100),2),'%'),'N/A') AS `Pass rate`,(select ifnull(group_concat(`TestCase`.`TestCaseName` separator ' '),'') from (`TestResult` left join `TestCase` on((`TestResult`.`TestCaseId` = `TestCase`.`TestCaseId`))) where ((`TestResult`.`TestRunId` = `TestRun`.`TestRunId`) and `TestResult`.`ResultId` in (select `ResultDict`.`ResultId` from `ResultDict` where (`ResultDict`.`ResultName` = 'Failed')))) AS `Failed test cases` from ((`TestRun` left join `ArchDict` on((`TestRun`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`TestRun`.`OSId` = `OSDict`.`OSId`))) where `TestRun`.`TestRunId` in (select max(`TestRun`.`TestRunId`) AS `TestRunId` from `TestRun` where (`TestRun`.`StartTime` > (now() - interval 2 day)) group by `TestRun`.`ArchId`,`TestRun`.`OSId`) order by `OSDict`.`OSName`,`ArchDict`.`ArchName` */;
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
/*!50001 VIEW `NinetyDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`NinetyDayReport`.`Passed`) AS `Passed`,sum(`NinetyDayReport`.`Failed`) AS `Failed`,sum(`NinetyDayReport`.`No run`) AS `No run`,sum(`NinetyDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`NinetyDayReport`.`Passed`) / (sum(`NinetyDayReport`.`Passed`) + sum(`NinetyDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`NinetyDayReport` left join `ArchDict` on((`NinetyDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`NinetyDayReport`.`OSId` = `OSDict`.`OSId`))) group by `NinetyDayReport`.`ArchId`,`NinetyDayReport`.`OSId` order by `OSDict`.`OSName`,`ArchDict`.`ArchName` */;
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
/*!50001 VIEW `SevenDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`SevenDayReport`.`Passed`) AS `Passed`,sum(`SevenDayReport`.`Failed`) AS `Failed`,sum(`SevenDayReport`.`No run`) AS `No run`,sum(`SevenDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`SevenDayReport`.`Passed`) / (sum(`SevenDayReport`.`Passed`) + sum(`SevenDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`SevenDayReport` left join `ArchDict` on((`SevenDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`SevenDayReport`.`OSId` = `OSDict`.`OSId`))) group by `SevenDayReport`.`ArchId`,`SevenDayReport`.`OSId` order by `OSDict`.`OSName`,`ArchDict`.`ArchName` */;
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
/*!50001 VIEW `ThirtyDayLookBack` AS select `ArchDict`.`ArchName` AS `Arch`,`OSDict`.`OSName` AS `OS`,count(0) AS `Test runs`,sum(`ThirtyDayReport`.`Passed`) AS `Passed`,sum(`ThirtyDayReport`.`Failed`) AS `Failed`,sum(`ThirtyDayReport`.`No run`) AS `No run`,sum(`ThirtyDayReport`.`Subtotal`) AS `Subtotal`,ifnull(concat(round(((sum(`ThirtyDayReport`.`Passed`) / (sum(`ThirtyDayReport`.`Passed`) + sum(`ThirtyDayReport`.`Failed`))) * 100),2),'%'),'N/A') AS `Pass rate` from ((`ThirtyDayReport` left join `ArchDict` on((`ThirtyDayReport`.`ArchId` = `ArchDict`.`ArchId`))) left join `OSDict` on((`ThirtyDayReport`.`OSId` = `OSDict`.`OSId`))) group by `ThirtyDayReport`.`ArchId`,`ThirtyDayReport`.`OSId` order by `OSDict`.`OSName`,`ArchDict`.`ArchName` */;
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

-- Dump completed on 2016-08-22  4:06:36
