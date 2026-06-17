@isTest
private class SFSMobileImageAnalyserControllerTest {
    @TestSetup
    static void setupTestData() {
        ServiceAppointment sa = new ServiceAppointment(
            EarliestStartTime = System.now(),
            DueDate = System.now().addDays(1)
        );
        insert sa;
    }

    @isTest
    static void testAnalyseImageMissingFileName() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        String base64Image = EncodingUtil.base64Encode(Blob.valueOf('Test image data'));

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(sa.Id, null, base64Image);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('File name'), 'Should mention missing file name');
        }
        Test.stopTest();
    }

    @isTest
    static void testAnalyseImageMissingBase64() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(sa.Id, 'test.jpg', null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('data'), 'Should mention missing file data');
        }
        Test.stopTest();
    }

    @isTest
    static void testAnalyseImageCreatesContentVersionOnly() {
        // Image should be stored but NOT linked to the SA until Save is called
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        String base64Image = EncodingUtil.base64Encode(Blob.valueOf('Test image data'));

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(sa.Id, 'test.jpg', base64Image);
            System.assert(false, 'Should have thrown exception — ConnectApi unavailable in test context');
        } catch (Exception e) {
            List<ContentVersion> cvList = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Title = 'test'];
            System.assertNotEquals(0, cvList.size(), 'ContentVersion should have been created');

            List<ContentDocumentLink> links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cvList[0].ContentDocumentId AND LinkedEntityId = :sa.Id
            ];
            System.assertEquals(0, links.size(), 'File should NOT be linked to SA before Save is called');
        }
        Test.stopTest();
    }

    @isTest
    static void testAnalyseImageWithoutRecordId() {
        String base64Image = EncodingUtil.base64Encode(Blob.valueOf('Test image data'));

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(null, 'test.jpg', base64Image);
            System.assert(false, 'Should have thrown exception — ConnectApi unavailable in test context');
        } catch (Exception e) {
            System.assert(true, 'Exception expected in test context');
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveAnalysisMissingRecordId() {
        Test.startTest();
        try {
            SFSMobileImageAnalyserController.saveAnalysis(null, 'Some analysis text', null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Record Id'), 'Should mention missing Record Id');
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveAnalysisMissingText() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        Test.startTest();
        try {
            SFSMobileImageAnalyserController.saveAnalysis(sa.Id, null, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Analysis text'), 'Should mention missing analysis text');
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveAnalysisWritesToServiceNote() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        Test.startTest();
        SFSMobileImageAnalyserController.saveAnalysis(sa.Id, 'Test analysis result', null);
        Test.stopTest();
        ServiceAppointment updated = [SELECT ServiceNote FROM ServiceAppointment WHERE Id = :sa.Id];
        System.assert(
            updated.ServiceNote.contains('Test analysis result'),
            'ServiceNote should contain the analysis text'
        );
        System.assert(
            updated.ServiceNote.contains('AI Image Analysis'),
            'ServiceNote should contain the section header'
        );
    }

    @isTest
    static void testSaveAnalysisAppendsToExistingNote() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        sa.ServiceNote = 'Existing technician note.';
        update sa;
        Test.startTest();
        SFSMobileImageAnalyserController.saveAnalysis(sa.Id, 'New AI analysis', null);
        Test.stopTest();
        ServiceAppointment updated = [SELECT ServiceNote FROM ServiceAppointment WHERE Id = :sa.Id];
        System.assert(updated.ServiceNote.contains('Existing technician note.'), 'Original note should be preserved');
        System.assert(updated.ServiceNote.contains('New AI analysis'), 'New analysis should be appended');
    }

    @isTest
    static void testSaveAnalysisLinksFileToServiceAppointment() {
        // Verify that Save links the ContentDocument to the SA
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'linktest',
            PathOnClient = 'linktest.jpg',
            VersionData = Blob.valueOf('Test image data'),
            Origin = 'H'
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        SFSMobileImageAnalyserController.saveAnalysis(sa.Id, 'Link test analysis', cv.ContentDocumentId);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId AND LinkedEntityId = :sa.Id
        ];
        System.assertNotEquals(0, links.size(), 'File should be linked to Service Appointment after Save');
    }

    @isTest
    static void testSaveAnalysisSkipsLinkWhenNoContentDocumentId() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        Integer linksBefore = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :sa.Id];

        Test.startTest();
        SFSMobileImageAnalyserController.saveAnalysis(sa.Id, 'Analysis without image', null);
        Test.stopTest();

        Integer linksAfter = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :sa.Id];
        System.assertEquals(
            linksBefore,
            linksAfter,
            'No new file links should be created when contentDocumentId is null'
        );
    }
}
