/**
 * STARTECH Frontend App
 * Xử lý: navigation mobile, load sản phẩm, smooth scroll, v.v.
 */
(function() {
  'use strict';

  // Mobile navigation toggle
  const navToggle = document.querySelector('.nav-toggle');
  const navMenu = document.querySelector('.nav-menu');

  if (navToggle && navMenu) {
    navToggle.addEventListener('click', () => {
      const expanded = navToggle.getAttribute('aria-expanded') === 'true';
      navToggle.setAttribute('aria-expanded', !expanded);
      navMenu.classList.toggle('open');
    });

    // Đóng menu khi click link
    navMenu.querySelectorAll('.nav-link').forEach(link => {
      link.addEventListener('click', () => {
        navToggle.setAttribute('aria-expanded', 'false');
        navMenu.classList.remove('open');
      });
    });

    // Đóng menu khi click ra ngoài
    document.addEventListener('click', (e) => {
      if (!navToggle.contains(e.target) && !navMenu.contains(e.target)) {
        navToggle.setAttribute('aria-expanded', 'false');
        navMenu.classList.remove('open');
      }
    });
  }

  // Active nav link highlighting
  const currentPath = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-link').forEach(link => {
    const href = link.getAttribute('href');
    if (href === currentPath || (currentPath === '' && href === 'index.html')) {
      link.classList.add('active');
    } else {
      link.classList.remove('active');
    }
  });

  // Load sản phẩm nổi bật (homepage)
  const productsGrid = document.getElementById('products-grid');
  if (productsGrid) {
    loadFeaturedProducts();
  }

  async function loadFeaturedProducts() {
    try {
      const response = await fetch('/api/products');
      if (!response.ok) throw new Error('Failed to load products');
      const products = await response.json();
      // Chỉ hiển thị 4 sản phẩm đầu
      const featured = products.slice(0, 4);
      productsGrid.innerHTML = featured.map(p => `
        <article class="product-card">
          <div class="product-image" aria-hidden="true">
            ${getProductIcon(p.category)}
          </div>
          <div class="product-info">
            <span class="product-category">${escapeHtml(p.category)}</span>
            <h3 class="product-name">${escapeHtml(p.name)}</h3>
            <div class="product-price">${formatPrice(p.price)}</div>
          </div>
        </article>
      `).join('');
    } catch (err) {
      console.error('[App] Load products failed:', err);
      productsGrid.innerHTML = '<p class="text-center" style="grid-column:1/-1;color:var(--color-text-muted);">Không thể tải sản phẩm lúc này.</p>';
    }
  }

  function getProductIcon(category) {
    const icons = {
      'Laptop': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="width:64px;height:64px;"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M2 17h20"/></svg>',
      'Thiết bị mạng': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="width:64px;height:64px;"><circle cx="12" cy="12" r="3"/><path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/></svg>',
      'Lưu trữ': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="width:64px;height:64px;"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>',
      default: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="width:64px;height:64px;"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 9h6M9 15h6"/></svg>'
    };
    return icons[category] || icons.default;
  }

  function formatPrice(price) {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(price);
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Smooth scroll cho anchor links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      const target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  // Console branding
  console.log('%cSTARTECH Frontend', 'color: #1e40af; font-size: 20px; font-weight: bold;');
  console.log('%cWebsite doanh nghiệp + Chatbot AI (Ollama + RAG)', 'color: #64748b;');

})();