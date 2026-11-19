#!/bin/bash
# Script xuất topology.drawio ra PNG cho báo cáo
# Cần cài: drawio-desktop (headless) hoặc dùng draw.io online

# Option 1: draw.io Desktop CLI (Linux/macOS)
# /Applications/draw.io.app/Contents/MacOS/draw.io -x -f png -o topology.png topology.drawio

# Option 2: draw.io Headless (Docker)
# docker run --rm -v $(pwd):/data jgraph/drawio -x -f png -o /data/topology.png /data/topology.drawio

# Option 3: Sử dụng draw.io online
# 1. Mở https://app.diagrams.net/
# 2. File > Import From > Device > Chọn topology.drawio
# 3. File > Export As > PNG > Tick "Transparent Background" > Export
# 4. Lưu thành topology.png vào thư mục này

echo "=== STARTECH Topology Export ==="
echo ""
echo "Cách xuất topology.drawio ra PNG:"
echo ""
echo "Cách 1: draw.io Online (khuyên dùng - không cần cài đặt)"
echo "  1. Mở https://app.diagrams.net/"
echo "  2. File > Import From > Device > Chọn file topology.drawio"
echo "  3. File > Export As > PNG"
echo "     - Tick 'Transparent Background'"
echo "     - Scale: 2.0 (cho báo cáo chất lượng cao)"
echo "     - Border: 20"
echo "  4. Lưu file topology.png vào thư mục này"
echo ""
echo "Cách 2: draw.io Desktop (nếu đã cài)"
echo "  draw.io -x -f png -o topology.png topology.drawio"
echo ""
echo "Cách 3: Docker (nếu có Docker)"
echo "  docker run --rm -v \$(pwd):/data jgraph/drawio -x -f png -o /data/topology.png /data/topology.drawio"
echo ""
echo "File topology.drawio đã sẵn sàng tại: $(pwd)/topology.drawio"
echo "Mở file này bằng draw.io để xem/sửa sơ đồ."