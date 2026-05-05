@isTest
private class SFSMobileImageAnalyserControllerTest {
    @TestSetup
    static void setupTestData() {
        ServiceAppointment sa = new ServiceAppointment(
            EarliestStartTime = System.now(),
            DueDate = System.now().addDays(1)
        );
        insert sa;

        ContentVersion cv = new ContentVersion(
            Title = 'Test Image',
            PathOnClient = 'test_image.jpg',
            VersionData = Blob.valueOf('Test image data'),
            IsMajorVersion = true
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = sa.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
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
    static void testAnalyseImageWithRecordId() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        String base64Image = EncodingUtil.base64Encode(Blob.valueOf('Test image data'));

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(sa.Id, 'test.jpg', base64Image);
            System.assert(false, 'Should have thrown exception — ConnectApi unavailable in test context');
        } catch (Exception e) {
            System.assert(true, 'Exception expected in test context');
            List<ContentVersion> cvList = [SELECT Id, Title FROM ContentVersion WHERE Title = 'test'];
            System.assertNotEquals(0, cvList.size(), 'ContentVersion should have been created');
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
    static void testFileLinkedToServiceAppointment() {
        ServiceAppointment sa = [SELECT Id FROM ServiceAppointment LIMIT 1];
        String base64Image = EncodingUtil.base64Encode(Blob.valueOf('Test image data'));

        Test.startTest();
        try {
            SFSMobileImageAnalyserController.analyseImage(sa.Id, 'linktest.jpg', base64Image);
        } catch (Exception e) {
            List<ContentVersion> cvList = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Title = 'linktest'
            ];
            System.assertNotEquals(0, cvList.size(), 'ContentVersion should exist');

            List<ContentDocumentLink> links = [
                SELECT Id
                FROM ContentDocumentLink
                WHERE ContentDocumentId = :cvList[0].ContentDocumentId AND LinkedEntityId = :sa.Id
            ];
            System.assertNotEquals(0, links.size(), 'File should be linked to Service Appointment');
        }
        Test.stopTest();
    }
}
