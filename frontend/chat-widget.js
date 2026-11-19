/**
 * STARTECH Chatbot Widget
 * Nhúng vào mọi trang website, giao tiếp với backend qua API
 * Dữ liệu không bao giờ rời khỏi mạng nội bộ (Ollama chạy local)
 */
(function() {
  'use strict';

  // Config - thay đổi khi deploy production
  const API_BASE = window.CHATBOT_API_BASE || '/api';
  const WIDGET_ID = 'startech-chat-widget';

  // Tạo session ID duy nhất cho mỗi trình duyệt
  function getSessionId() {
    let sid = sessionStorage.getItem('startech_chat_session');
    if (!sid) {
      sid = 'sess_' + Date.now() + '_' + Math.random().toString(36).slice(2, 9);
      sessionStorage.setItem('startech_chat_session', sid);
    }
    return sid;
  }

  // Escape HTML để防 XSS
  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Format timestamp
  function formatTime(date) {
    return date.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
  }

  // Tạo widget HTML
  function createWidgetHTML() {
    return `
      <div class="chat-widget" id="${WIDGET_ID}" role="region" aria-label="Chatbot STARTECH">
        <button class="chat-toggle" id="chat-toggle" aria-expanded="false" aria-controls="chat-window" aria-label="Mở chat hỗ trợ">
          <svg class="chat-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
          </svg>
          <svg class="close-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>

        <div class="chat-window" id="chat-window" role="dialog" aria-label="Hội thoại chatbot">
          <div class="chat-header">
            <h3>Hỗ trợ STARTECH</h3>
            <button class="chat-minimize" id="chat-minimize" aria-label="Đóng chat">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </div>

          <div class="chat-messages" id="chat-messages" role="log" aria-live="polite" aria-label="Tin nhắn">
            <div class="message bot" data-time="${formatTime(new Date())}">
              Xin chào! Tôi là trợ lý ảo của STARTECH. Tôi có thể giúp bạn:<br>
              • Hỏi giá sản phẩm (laptop, thiết bị mạng, lưu trữ)<br>
              • Tra cứu chính sách bảo hành, đổi trả<br>
              • Hỏi giờ làm việc, địa chỉ chi nhánh<br>
              • Hỗ trợ đặt hàng, tư vấn giải pháp<br><br>
              Bạn muốn hỏi gì hôm nay?
            </div>
          </div>

          <div class="chat-input-area">
            <div class="chat-input-wrapper">
              <input type="text" class="chat-input" id="chat-input" placeholder="Nhập câu hỏi..." autocomplete="off" aria-label="Nhập tin nhắn" maxlength="1000">
              <button class="chat-send" id="chat-send" aria-label="Gửi tin nhắn" disabled>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/>
                </svg>
              </button>
            </div>
            <p class="chat-disclaimer">Chatbot AI chạy nội bộ, dữ liệu không rời khỏi mạng doanh nghiệp.</p>
          </div>
        </div>
      </div>
    `;
  }

  // Khởi tạo widget
  function initWidget() {
    if (document.getElementById(WIDGET_ID)) return; // đã có

    const container = document.createElement('div');
    container.id = 'chatbot-widget-container';
    container.innerHTML = createWidgetHTML();
    document.body.appendChild(container);

    const toggle = document.getElementById('chat-toggle');
    const window_el = document.getElementById('chat-window');
    const minimize = document.getElementById('chat-minimize');
    const input = document.getElementById('chat-input');
    const sendBtn = document.getElementById('chat-send');
    const messages = document.getElementById('chat-messages');

    let isOpen = false;

    // Toggle widget
    function toggleWidget() {
      isOpen = !isOpen;
      toggle.classList.toggle('open', isOpen);
      window_el.classList.toggle('open', isOpen);
      toggle.setAttribute('aria-expanded', isOpen);
      if (isOpen) {
        input.focus();
        scrollToBottom();
      }
    }

    toggle.addEventListener('click', toggleWidget);
    minimize.addEventListener('click', () => { if (isOpen) toggleWidget(); });

    // Input validation
    input.addEventListener('input', () => {
      sendBtn.disabled = !input.value.trim();
    });

    // Enter để gửi
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (!sendBtn.disabled) sendMessage();
      }
    });

    sendBtn.addEventListener('click', sendMessage);

    // Gửi tin nhắn
    async function sendMessage() {
      const text = input.value.trim();
      if (!text) return;

      // Hiển thị tin nhắn user ngay
      appendMessage(text, 'user');
      input.value = '';
      sendBtn.disabled = true;

      // Hiển thị typing indicator
      const typingId = showTyping();

      try {
        const response = await fetch(`${API_BASE}/chat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: text,
            sessionId: getSessionId()
          })
        });

        const data = await response.json();
        hideTyping(typingId);

        if (data.blocked) {
          appendMessage(data.answer, 'bot', true);
        } else {
          appendMessage(data.answer, 'bot');
          // Có thể hiển thị sources nếu muốn
          if (data.sources && data.sources.length > 0) {
            console.log('[Chatbot] Sources:', data.sources);
          }
        }
      } catch (err) {
        hideTyping(typingId);
        appendMessage('Xin lỗi, không thể kết nối đến máy chủ chatbot. Vui lòng thử lại sau.', 'bot', true);
        console.error('[Chatbot] Error:', err);
      }
    }

    // Thêm tin nhắn vào UI
    function appendMessage(text, type, isError = false) {
      const div = document.createElement('div');
      div.className = `message ${type}${isError ? ' error' : ''}`;
      div.setAttribute('data-time', formatTime(new Date()));
      div.innerHTML = escapeHtml(text).replace(/\n/g, '<br>');
      messages.appendChild(div);
      scrollToBottom();
    }

    // Typing indicator
    function showTyping() {
      const id = 'typing_' + Date.now();
      const div = document.createElement('div');
      div.id = id;
      div.className = 'message bot typing';
      div.innerHTML = '<span class="typing-dot"></span><span class="typing-dot"></span><span class="typing-dot"></span>';
      messages.appendChild(div);
      scrollToBottom();
      return id;
    }

    function hideTyping(id) {
      const el = document.getElementById(id);
      if (el) el.remove();
    }

    function scrollToBottom() {
      messages.scrollTop = messages.scrollHeight;
    }
  }

  // Khởi tạo khi DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initWidget);
  } else {
    initWidget();
  }

  // Export cho debugging
  window.StartechChat = { initWidget };
})();