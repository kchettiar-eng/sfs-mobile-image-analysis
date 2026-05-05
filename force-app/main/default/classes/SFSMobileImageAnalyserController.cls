/**
 * Controller for SFS Mobile Image Analyser LWC.
 * Deployed as a Quick Action on the ServiceAppointment object.
 * Uses ConnectApi.EinsteinLLM to invoke the SFS_Mobile_Image_Analysis prompt template.
 */
public with sharing class SFSMobileImageAnalyserController {
    private static final String PROMPT_TEMPLATE_API_NAME = 'SFS_Mobile_Image_Analysis';

    @AuraEnabled
    public static String analyseImage(String recordId, String fileName, String base64Data) {
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

            if (String.isNotBlank(recordId)) {
                cv.FirstPublishLocationId = recordId;
            }

            insert cv;

            ContentVersion inserted = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];

            if (String.isNotBlank(recordId)) {
                List<ContentDocumentLink> existing = [
                    SELECT Id
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId = :inserted.ContentDocumentId AND LinkedEntityId = :recordId
                    LIMIT 1
                ];
                if (existing.isEmpty()) {
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = inserted.ContentDocumentId;
                    cdl.LinkedEntityId = recordId;
                    cdl.ShareType = 'V';
                    cdl.Visibility = 'AllUsers';
                    insert cdl;
                }
            }

            return invokePromptTemplate(inserted.ContentDocumentId);
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
}
