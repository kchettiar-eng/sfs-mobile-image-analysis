/**
 * Controller for SFS Mobile Image Analyser LWC.
 * Deployed as a Quick Action on the ServiceAppointment object.
 * Uses ConnectApi.EinsteinLLM to invoke the SFS_Mobile_Image_Analysis prompt template.
 */
public with sharing class SFSMobileImageAnalyserController {
    private static final String PROMPT_TEMPLATE_API_NAME = 'SFS_Mobile_Image_Analysis';

    public class AnalysisResult {
        @AuraEnabled
        public String aiResponse;
        @AuraEnabled
        public String contentDocumentId;
    }

    @AuraEnabled
    public static AnalysisResult analyseImage(String recordId, String fileName, String base64Data) {
        Savepoint sp = Database.setSavepoint();
        try {
            if (String.isBlank(fileName)) {
                throw new AuraHandledException('File name is required.');
            }
            if (String.isBlank(base64Data)) {
                throw new AuraHandledException('File data is required.');
            }

            Blob fileBlob = EncodingUtil.base64Decode(base64Data);

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName.substringBeforeLast('.');
            cv.PathOnClient = fileName;
            cv.VersionData = fileBlob;
            cv.Origin = 'H';
            insert cv;

            ContentVersion inserted = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];

            AnalysisResult result = new AnalysisResult();
            result.aiResponse = invokePromptTemplate(inserted.ContentDocumentId);
            result.contentDocumentId = inserted.ContentDocumentId;
            return result;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'SFSMobileImageAnalyserController.analyseImage error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            throw new AuraHandledException('Error analysing image: ' + e.getMessage());
        }
    }

    private static String invokePromptTemplate(Id contentDocumentId) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;

        ConnectApi.WrappedValue imageInput = new ConnectApi.WrappedValue();
        imageInput.value = new Map<String, String>{
            'id' => String.valueOf(contentDocumentId),
            'type' => 'ContentDocument'
        };

        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Image_Data' => imageInput };

        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
            PROMPT_TEMPLATE_API_NAME,
            input
        );

        if (response != null && response.generations != null && !response.generations.isEmpty()) {
            ConnectApi.EinsteinLLMGenerationItemOutput generation = response.generations[0];
            if (generation != null && String.isNotBlank(generation.text)) {
                return generation.text;
            }
        }

        throw new AuraHandledException('No response received from the AI model. Please try again.');
    }

    @AuraEnabled
    public static void saveAnalysis(String recordId, String analysisText, String contentDocumentId) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record Id is required.');
            }
            if (String.isBlank(analysisText)) {
                throw new AuraHandledException('Analysis text is required.');
            }

            ServiceAppointment sa = [SELECT Id, ServiceNote FROM ServiceAppointment WHERE Id = :recordId LIMIT 1];
            String timestamp = DateTime.now().format('dd MMM yyyy HH:mm', UserInfo.getTimeZone().getID());
            String newEntry = '--- AI Image Analysis (' + timestamp + ') ---\n' + analysisText;
            sa.ServiceNote = String.isBlank(sa.ServiceNote) ? newEntry : sa.ServiceNote + '\n\n' + newEntry;
            update sa;

            if (String.isNotBlank(contentDocumentId)) {
                List<ContentDocumentLink> existing = [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :recordId
                    LIMIT 1
                ];
                if (existing.isEmpty()) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = contentDocumentId;
                    cdl.LinkedEntityId = recordId;
                    cdl.ShareType = 'V';
                    cdl.Visibility = 'AllUsers';
                    insert cdl;
                }
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SFSMobileImageAnalyserController.saveAnalysis error: ' + e.getMessage());
            throw new AuraHandledException('Error saving analysis: ' + e.getMessage());
        }
    }
}
