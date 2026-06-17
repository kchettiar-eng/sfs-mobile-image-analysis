/**
 * Invocable method to trigger SFS Mobile Image Analysis from a Flow.
 */
public with sharing class SFSMobileImageAnalysisInvocable {
    @InvocableMethod(
        label='Analyse Image with AI (SFS Mobile)'
        description='Calls the SFS Mobile Image Analysis Prompt Template to analyse an image attached to a Service Appointment'
        category='Einstein'
    )
    public static List<Result> analyseImage(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result result = new Result();
            try {
                SFSMobileImageAnalyserController.AnalysisResult ar = SFSMobileImageAnalyserController.analyseImage(
                    req.recordId,
                    req.fileName,
                    req.base64Data
                );
                result.analysisResult = ar.aiResponse;
                result.contentDocumentId = ar.contentDocumentId;
                result.success = true;
            } catch (Exception e) {
                result.analysisResult = 'Error: ' + e.getMessage();
                result.success = false;
                System.debug(LoggingLevel.ERROR, 'SFSMobileImageAnalysisInvocable error: ' + e.getMessage());
            }
            results.add(result);
        }
        return results;
    }

    public class Request {
        @InvocableVariable(label='Service Appointment Record Id' required=true)
        public String recordId;

        @InvocableVariable(label='File Name' required=true)
        public String fileName;

        @InvocableVariable(label='Image Data (Base64)' required=true)
        public String base64Data;
    }

    public class Result {
        @InvocableVariable(label='Analysis Result')
        public String analysisResult;

        @InvocableVariable(label='Content Document Id')
        public String contentDocumentId;

        @InvocableVariable(label='Success')
        public Boolean success;
    }
}
