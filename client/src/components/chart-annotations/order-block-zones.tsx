import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface OriginZone {
  start: number;
  end: number;
}

interface OrderBlockZonesProps {
  zones: OriginZone[];
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
  direction: "long" | "short" | "none";
}

export function OrderBlockZones({
  zones,
  priceRange,
  imageWidth,
  imageHeight,
  direction,
}: OrderBlockZonesProps) {
  const fontSize = Math.max(11, imageHeight * 0.018);

  // Bullish OB (for longs) = blue, Bearish OB (for shorts) = red
  const isBullish = direction === "long";
  const fillColor = isBullish ? "#3b82f6" : "#ef4444";
  const labelBg = isBullish ? "#2563eb" : "#dc2626";
  const label = isBullish ? "BULLISH OB" : "BEARISH OB";

  return (
    <g className="order-block-zones">
      {zones.map((zone, i) => {
        const y1 = priceToY(zone.start, priceRange, imageHeight);
        const y2 = priceToY(zone.end, priceRange, imageHeight);
        const top = Math.min(y1, y2);
        const height = Math.abs(y2 - y1);

        // Skip if zone is outside visible area
        if (top > imageHeight || top + height < 0) return null;

        return (
          <g key={`ob-${i}`}>
            {/* Semi-transparent filled rectangle */}
            <rect
              x={0}
              y={top}
              width={imageWidth}
              height={Math.max(height, 4)}
              fill={fillColor}
              fillOpacity="0.15"
            />
            {/* Border lines */}
            <line
              x1={0}
              y1={top}
              x2={imageWidth}
              y2={top}
              stroke={fillColor}
              strokeWidth="1.5"
              strokeOpacity="0.6"
            />
            <line
              x1={0}
              y1={top + height}
              x2={imageWidth}
              y2={top + height}
              stroke={fillColor}
              strokeWidth="1.5"
              strokeOpacity="0.6"
            />
            {/* Label */}
            <rect
              x={imageWidth * 0.02}
              y={top + 4}
              width={direction === "none" ? 30 : 90}
              height={fontSize + 6}
              fill={labelBg}
              fillOpacity="0.9"
              rx="3"
            />
            <text
              x={imageWidth * 0.02 + 6}
              y={top + 4 + (fontSize + 6) / 2}
              fill="white"
              fontSize={fontSize}
              fontWeight="700"
              dominantBaseline="middle"
            >
              {direction === "none" ? "OB" : label}
            </text>
            {/* Price range label */}
            <rect
              x={imageWidth * 0.02}
              y={top + height - fontSize - 10}
              width={100}
              height={fontSize + 4}
              fill="rgba(0,0,0,0.7)"
              rx="2"
            />
            <text
              x={imageWidth * 0.02 + 5}
              y={top + height - 6}
              fill="white"
              fontSize={fontSize - 1}
              fontFamily="monospace"
              dominantBaseline="middle"
            >
              {zone.start.toFixed(zone.start >= 100 ? 2 : 5)} - {zone.end.toFixed(zone.end >= 100 ? 2 : 5)}
            </text>
          </g>
        );
      })}
    </g>
  );
}
