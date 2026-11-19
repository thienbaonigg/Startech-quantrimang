/**
 * STARTECH Contact Form Handler
 * Xử lý form liên hệ (demo - thực tế gửi lên backend API)
 */
(function() {
  'use strict';

  const form = document.getElementById('contact-form');
  const successDiv = document.getElementById('form-success');
  const resetBtn = document.getElementById('form-reset');

  if (!form) return;

  // Validation
  function validateField(field) {
    const errorId = field.id + '-error';
    let errorEl = document.getElementById(errorId);

    if (!field.checkValidity()) {
      if (!errorEl) {
        errorEl = document.createElement('div');
        errorEl.id = errorId;
        errorEl.className = 'field-error';
        errorEl.setAttribute('role', 'alert');
        field.parentNode.appendChild(errorEl);
      }
      errorEl.textContent = getErrorMessage(field);
      field.setAttribute('aria-invalid', 'true');
      return false;
    } else {
      if (errorEl) errorEl.remove();
      field.setAttribute('aria-invalid', 'false');
      return true;
    }
  }

  function getErrorMessage(field) {
    if (field.validity.valueMissing) return `${getFieldLabel(field)} là bắt buộc.`;
    if (field.validity.typeMismatch) {
      if (field.type === 'email') return 'Email không hợp lệ.';
      if (field.type === 'tel') return 'Số điện thoại không hợp lệ.';
    }
    if (field.validity.tooShort) return `${getFieldLabel(field)} quá ngắn (tối thiểu ${field.minLength} ký tự).`;
    return 'Giá trị không hợp lệ.';
  }

  function getFieldLabel(field) {
    const label = document.querySelector(`label[for="${field.id}"]`);
    return label ? label.textContent.replace('*', '').trim() : 'Trường này';
  }

  // Real-time validation
  form.querySelectorAll('input, select, textarea').forEach(field => {
    field.addEventListener('blur', () => validateField(field));
    field.addEventListener('input', () => {
      if (field.getAttribute('aria-invalid') === 'true') validateField(field);
    });
  });

  // Submit handler
  form.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Validate all
    let isValid = true;
    form.querySelectorAll('input, select, textarea').forEach(field => {
      if (!validateField(field)) isValid = false;
    });

    if (!isValid) {
      const firstInvalid = form.querySelector('[aria-invalid="true"]');
      if (firstInvalid) firstInvalid.focus();
      return;
    }

    // Collect data
    const formData = new FormData(form);
    const data = Object.fromEntries(formData.entries());

    // Show loading
    const submitBtn = form.querySelector('button[type="submit"]');
    const originalText = submitBtn.innerHTML;
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<svg class="spinner" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width:20px;height:20px;animation:spin 1s linear infinite;"><circle cx="12" cy="12" r="10" stroke-opacity="0.25"/><path d="M12 2a10 10 0 0 1 10 10" stroke-opacity="1"/></svg> Đang gửi...';

    // Simulate API call (replace with real fetch to backend)
    try {
      // await fetch('/api/contact', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
      await new Promise(r => setTimeout(r, 1500)); // Simulate network delay
      console.log('[Contact] Form submitted:', data);

      // Show success
      form.hidden = true;
      successDiv.hidden = false;
    } catch (err) {
      console.error('[Contact] Submit failed:', err);
      submitBtn.disabled = false;
      submitBtn.innerHTML = originalText;
      alert('Gửi thất bại. Vui lòng thử lại hoặc liên hệ hotline 028.1234.5678.');
    }
  });

  // Reset form
  resetBtn.addEventListener('click', () => {
    form.reset();
    form.hidden = false;
    successDiv.hidden = true;
    form.querySelectorAll('[aria-invalid="true"]').forEach(f => f.setAttribute('aria-invalid', 'false'));
    form.querySelectorAll('.field-error').forEach(e => e.remove());
  });

  // Add spinner animation
  const style = document.createElement('style');
  style.textContent = `
    @keyframes spin { to { transform: rotate(360deg); } }
    .field-error { color: var(--color-error); font-size: 0.8rem; margin-top: 4px; }
    input[aria-invalid="true"], select[aria-invalid="true"], textarea[aria-invalid="true"] { border-color: var(--color-error); }
    input[aria-invalid="true"]:focus, select[aria-invalid="true"]:focus, textarea[aria-invalid="true"]:focus { box-shadow: 0 0 0 3px rgba(239,68,68,0.1); }
  `;
  document.head.appendChild(style);
})();