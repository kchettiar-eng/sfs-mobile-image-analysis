import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import analyseImage from '@salesforce/apex/SFSMobileImageAnalyserController.analyseImage';

export default class SfsMobileImageAnalyser extends LightningElement {
    @api recordId;

    @track selectedFile = null;
    @track selectedFileName = '';
    @track selectedFileSize = 0;
    @track base64Data = '';
    @track imagePreviewUrl = '';

    @track isProcessing = false;
    @track hasError = false;
    @track errorMessage = '';
    @track hasResult = false;
    @track aiResponse = '';
    @track hasSaved = false;
    @track isOnline = true;

    maxFileSizeMB = 10;
    acceptedFormats = '.jpg,.jpeg,.png';
    validExtensions = ['.jpg', '.jpeg', '.png'];
    validMimeTypes = ['image/jpeg', 'image/png'];

    connectedCallback() {
        this.isOnline = navigator.onLine;
        window.addEventListener('online', this._handleOnlineChange.bind(this));
        window.addEventListener('offline', this._handleOnlineChange.bind(this));
    }

    disconnectedCallback() {
        window.removeEventListener('online', this._handleOnlineChange.bind(this));
        window.removeEventListener('offline', this._handleOnlineChange.bind(this));
    }

    _handleOnlineChange() {
        this.isOnline = navigator.onLine;
        if (this.isOnline && this.hasError && this.errorMessage.includes('offline')) {
            this.hasError = false;
            this.errorMessage = '';
        }
    }

    // ── Getters ──────────────────────────────────────────────────────────────

    get isOffline() { return !this.isOnline; }

    get showDropzone() { return !this.hasSelectedFile; }

    get hasSelectedFile() {
        return this.selectedFile !== null && this.selectedFileName !== '';
    }

    get formattedFileSize() {
        if (!this.selectedFileSize) return '';
        const kb = this.selectedFileSize / 1024;
        return kb < 1024 ? `${kb.toFixed(1)} KB` : `${(kb / 1024).toFixed(2)} MB`;
    }

    get isAnalyseDisabled() {
        return !this.hasSelectedFile || this.isProcessing || this.isOffline;
    }

    get maxFileSize() { return this.maxFileSizeMB * 1024 * 1024; }

    get stepClass1() { return 'step-item' + (!this.hasSelectedFile ? ' step-active' : ' step-complete'); }
    get stepClass2() { return 'step-item' + (this.hasSelectedFile && !this.hasResult && !this.hasSaved ? ' step-active' : (this.hasResult || this.hasSaved) ? ' step-complete' : ''); }
    get stepClass3() { return 'step-item' + (this.hasResult || this.hasSaved ? ' step-complete' : ''); }
    get stepDot1()   { return 'step-dot' + (!this.hasSelectedFile ? ' step-dot--active' : ' step-dot--complete'); }
    get stepDot2()   { return 'step-dot' + (this.hasSelectedFile && !this.hasResult && !this.hasSaved ? ' step-dot--active' : (this.hasResult || this.hasSaved) ? ' step-dot--complete' : ''); }
    get stepDot3()   { return 'step-dot' + (this.hasResult || this.hasSaved ? ' step-dot--complete' : ''); }
    get stepConnector12() { return 'step-connector' + (this.hasSelectedFile ? ' step-connector--done' : ''); }
    get stepConnector23() { return 'step-connector' + (this.hasResult || this.hasSaved ? ' step-connector--done' : ''); }

    // ── File upload ───────────────────────────────────────────────────────────

    stopPropagation(event) { event.stopPropagation(); }

    triggerFileInput(event) {
        if (event) event.stopPropagation();
        this.template.querySelector('input[type="file"]').click();
    }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (file.size > this.maxFileSize) {
            this._showError(`File size exceeds the ${this.maxFileSizeMB} MB limit. Please select a smaller file.`);
            return;
        }

        const ext = file.name.toLowerCase().substring(file.name.lastIndexOf('.'));
        if (!this.validExtensions.includes(ext)) {
            this._showError('Unsupported file type. Please use JPG or PNG files only.');
            return;
        }

        if (!this.validMimeTypes.includes(file.type)) {
            this._showError('Invalid file format detected. Please select a valid JPG or PNG file.');
            return;
        }

        this._clearState();
        this.selectedFile = file;
        this.selectedFileName = file.name;
        this.selectedFileSize = file.size;

        const reader = new FileReader();
        reader.onload = () => {
            this.imagePreviewUrl = reader.result;
            this.base64Data = reader.result.split(',')[1];
        };
        reader.onerror = () => this._showError('Failed to read the file. Please try again.');
        reader.readAsDataURL(file);
    }

    // ── Analyse ───────────────────────────────────────────────────────────────

    async handleAnalyse() {
        if (!navigator.onLine) {
            this.isOnline = false;
            this._showError('You are currently offline. AI analysis requires an internet connection.');
            return;
        }

        if (!this.base64Data || !this.selectedFileName) {
            this._showError('Please select a file first.');
            return;
        }

        this.isProcessing = true;
        this.hasError = false;
        this.errorMessage = '';
        this.hasResult = false;

        try {
            this.aiResponse = await analyseImage({
                recordId: this.recordId,
                fileName: this.selectedFileName,
                base64Data: this.base64Data
            });
            this.hasResult = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Analysis Complete',
                message: 'The image has been analysed successfully.',
                variant: 'success'
            }));
        } catch (error) {
            let msg = 'An unexpected error occurred. Please try again.';
            if (error.body?.message) msg = error.body.message;
            else if (error.message) msg = error.message;
            this._showError(msg);
        } finally {
            this.isProcessing = false;
        }
    }

    // ── Save to Service Appointment ───────────────────────────────────────────

    async handleSave() {
        this.hasResult = false;
        this.hasSaved = true;
        this.dispatchEvent(new ShowToastEvent({
            title: 'Saved',
            message: 'Analysis saved to this Service Appointment.',
            variant: 'success'
        }));
    }

    // ── Copy ──────────────────────────────────────────────────────────────────

    async handleCopyResult() {
        try {
            await navigator.clipboard.writeText(this.aiResponse);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Copied',
                message: 'Analysis result copied to clipboard.',
                variant: 'success'
            }));
        } catch {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Copy Failed',
                message: 'Unable to copy to clipboard. Please select and copy manually.',
                variant: 'warning'
            }));
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    handleAnalyseAnother() {
        this._clearState();
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) fileInput.value = '';
    }

    handleDone() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _showError(message) {
        this.hasError = true;
        this.errorMessage = message;
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error',
            mode: 'sticky'
        }));
    }

    _clearState() {
        this.selectedFile     = null;
        this.selectedFileName = '';
        this.selectedFileSize = 0;
        this.base64Data       = '';
        this.imagePreviewUrl  = '';
        this.hasError         = false;
        this.errorMessage     = '';
        this.hasResult        = false;
        this.aiResponse       = '';
        this.hasSaved         = false;
    }
}
