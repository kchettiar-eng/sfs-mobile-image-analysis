import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import analyseImage from '@salesforce/apex/SFSMobileImageAnalyserController.analyseImage';
import saveAnalysis from '@salesforce/apex/SFSMobileImageAnalyserController.saveAnalysis';

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
    @track contentDocumentId = '';
    @track hasSaved = false;
    @track isSaving = false;
    @track isOnline = true;

    maxFileSizeMB = 10;
    acceptedFormats = '.jpg,.jpeg,.png';
    validExtensions = ['.jpg', '.jpeg', '.png'];
    validMimeTypes = ['image/jpeg', 'image/png'];

    // Image compression constants
    _MAX_DIMENSION   = 1920;
    _MAX_BYTES       = 1024 * 1024; // 1 MB compressed target
    _QUALITY_START   = 0.85;
    _QUALITY_MIN     = 0.40;
    _QUALITY_STEP    = 0.05;

    renderedCallback() {
        if (this.hasResult) {
            const el = this.template.querySelector('.results-rich-text-wrap');
            if (el) el.innerHTML = this.formattedAiResponse;
        }
    }

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

    get formattedAiResponse() {
        if (!this.aiResponse) return '';

        const lines = this.aiResponse.split('\n');
        let html = '';
        let inList = false;
        let inRecommendedActions = false;

        const bold = (text) => text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

        // Inline styles used throughout — lwc:inner-html injected nodes are outside LWC's CSS
        // scoping token, so component stylesheet rules won't match them reliably.
        const S = {
            h2:    'font-size:1rem;font-weight:700;margin:.75rem 0 .25rem;color:#032e61;',
            h3:    'font-size:.875rem;font-weight:700;margin:.625rem 0 .25rem;color:#181818;',
            h3red: 'font-size:.875rem;font-weight:700;margin:.625rem 0 .25rem;color:#c23934;',
            h4:    'font-size:.8125rem;font-weight:700;margin:.5rem 0 .125rem;color:#3e3e3c;',
            h4red: 'font-size:.8125rem;font-weight:700;margin:.5rem 0 .125rem;color:#c23934;',
            hr:    'border:none;border-top:1px solid #e0e5ee;margin:.75rem 0;',
            ul:    'padding-left:1.25rem;margin:.25rem 0;',
            li:    'margin-bottom:.2rem;font-size:.8125rem;line-height:1.6;color:#3e3e3c;',
            lired: 'margin-bottom:.2rem;font-size:.8125rem;line-height:1.6;color:#c23934;',
            p:     'margin:.25rem 0;font-size:.8125rem;line-height:1.6;color:#3e3e3c;',
            pred:  'margin:.25rem 0;font-size:.8125rem;line-height:1.6;color:#c23934;'
        };

        const closeList = () => {
            if (inList) { html += '</ul>'; inList = false; }
        };

        for (const line of lines) {
            if ((line.startsWith('#') || line.trim() === '---' || line.trim() === '') && inList) {
                closeList();
            }

            if (line.startsWith('# ')) {
                html += `<p style="${S.h2}"><strong>${bold(line.slice(2).trim())}</strong></p>`;
            } else if (line.startsWith('## ')) {
                const text = line.slice(3).trim();
                inRecommendedActions = /recommended\s+actions/i.test(text);
                const style = inRecommendedActions ? S.h3red : S.h3;
                html += `<p style="${style}"><strong>${bold(text)}</strong></p>`;
            } else if (line.startsWith('### ')) {
                const text = line.slice(4).trim();
                const style = inRecommendedActions ? S.h4red : S.h4;
                html += `<p style="${style}"><strong>${bold(text)}</strong></p>`;
            } else if (line.trim() === '---') {
                inRecommendedActions = false;
                html += `<hr style="${S.hr}"/>`;
            } else if (line.startsWith('- ') || line.startsWith('* ')) {
                const text = bold(line.slice(2).trim());
                const liStyle = inRecommendedActions ? S.lired : S.li;
                if (!inList) { html += `<ul style="${S.ul}">`; inList = true; }
                html += `<li style="${liStyle}">${text}</li>`;
            } else if (line.trim() === '') {
                html += `<p style="margin:.25rem 0;"></p>`;
            } else {
                const text = bold(line.trim());
                const style = inRecommendedActions ? S.pred : S.p;
                html += `<p style="${style}">${text}</p>`;
            }
        }

        closeList();
        return html;
    }

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
        reader.onload = (e) => this._compressImage(e.target.result);
        reader.onerror = () => this._showError('Failed to read the file. Please try again.');
        reader.readAsDataURL(file);
    }

    _compressImage(dataUrl) {
        const img = new Image();
        img.onload = () => {
            let w = img.naturalWidth  || img.width;
            let h = img.naturalHeight || img.height;

            if (w > this._MAX_DIMENSION || h > this._MAX_DIMENSION) {
                const ratio = Math.min(this._MAX_DIMENSION / w, this._MAX_DIMENSION / h);
                w = Math.round(w * ratio);
                h = Math.round(h * ratio);
            }

            const canvas = document.createElement('canvas');
            canvas.width  = w;
            canvas.height = h;
            canvas.getContext('2d').drawImage(img, 0, 0, w, h);

            let quality    = this._QUALITY_START;
            let compressed = canvas.toDataURL('image/jpeg', quality);
            while (this._base64Bytes(compressed) > this._MAX_BYTES && quality > this._QUALITY_MIN) {
                quality    = Math.round((quality - this._QUALITY_STEP) * 100) / 100;
                compressed = canvas.toDataURL('image/jpeg', quality);
            }

            if (this._base64Bytes(compressed) > this._MAX_BYTES) {
                this._showError('Image is too large to process even after compression. Please use a smaller or lower-resolution photo.');
                return;
            }

            this.imagePreviewUrl = compressed;
            this.base64Data      = compressed.split(',')[1];
        };
        img.onerror = () => this._showError('Failed to process the image. Please try again.');
        img.src = dataUrl;
    }

    _base64Bytes(dataUrl) {
        const b64 = dataUrl.includes(',') ? dataUrl.split(',')[1] : dataUrl;
        return Math.ceil((b64.length * 3) / 4);
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
            const result = await analyseImage({
                recordId: this.recordId,
                fileName: this.selectedFileName,
                base64Data: this.base64Data
            });
            this.aiResponse = result.aiResponse;
            this.contentDocumentId = result.contentDocumentId;
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
        this.isSaving = true;
        try {
            await saveAnalysis({
                recordId: this.recordId,
                analysisText: this.aiResponse,
                contentDocumentId: this.contentDocumentId
            });
            this.hasResult = false;
            this.hasSaved = true;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved',
                message: 'Analysis saved to this Service Appointment.',
                variant: 'success'
            }));
        } catch (error) {
            let msg = 'An unexpected error occurred. Please try again.';
            if (error.body?.message) msg = error.body.message;
            else if (error.message) msg = error.message;
            this._showError(msg);
        } finally {
            this.isSaving = false;
        }
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
        this.selectedFile        = null;
        this.selectedFileName    = '';
        this.selectedFileSize    = 0;
        this.base64Data          = '';
        this.imagePreviewUrl     = '';
        this.hasError            = false;
        this.errorMessage        = '';
        this.hasResult           = false;
        this.aiResponse          = '';
        this.contentDocumentId   = '';
        this.hasSaved            = false;
    }
}
