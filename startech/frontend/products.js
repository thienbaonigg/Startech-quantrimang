/**
 * STARTECH Products Page
 * Tải và lọc sản phẩm theo danh mục
 */
(function() {
  'use strict';

  const productsGrid = document.getElementById('products-grid');
  const tabButtons = document.querySelectorAll('.tab-btn');
  let allProducts = [];

  // Load tất cả sản phẩm
  async function loadProducts() {
    try {
      const response = await fetch('/api/products');
      if (!response.ok) throw new Error('Failed to load');
      allProducts = await response.json();
      renderProducts('all');
    } catch (err) {
      console.error('[Products] Load failed:', err);
      productsGrid.innerHTML = '<p style="grid-column:1/-1;text-align:center;color:var(--color-text-muted);padding:40px;">Không thể tải danh sách sản phẩm.</p>';
    }
  }

  // Render sản phẩm theo danh mục
  function renderProducts(category) {
    const filtered = category === 'all'
      ? allProducts
      : allProducts.filter(p => p.category === category);

    if (filtered.length === 0) {
      productsGrid.innerHTML = '<p style="grid-column:1/-1;text-align:center;color:var(--color-text-muted);padding:40px;">Không có sản phẩm trong danh mục này.</p>';
      return;
    }

    productsGrid.innerHTML = filtered.map(p => `
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
  }

  // Event listeners cho tabs
  tabButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      tabButtons.forEach(b => {
        b.classList.remove('active');
        b.setAttribute('aria-selected', 'false');
      });
      btn.classList.add('active');
      btn.setAttribute('aria-selected', 'true');
      renderProducts(btn.dataset.category);
    });
  });

  // Utility
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

  // Initialize
  loadProducts();
})();