import { priceToY } from "./annotated-chart";

interface PriceRange {
  minPrice: number;
  maxPrice: number;
}

interface TargetLinesProps {
  targets: number[];
  priceRange: PriceRange;
  imageWidth: number;
  imageHeight: number;
}

export function TargetLines({
  targets,
  priceRange,
  imageWidth,
  imageHeight,
}: TargetLinesProps) {
  const fontSize = Math.max(11, imageHeight * 0.018);

  // Color gradient for targets - lighter green for further targets
  const getTargetColor = (index: number): string => {
    const colors = ["#10b981", "#34d399", "#6ee7b7", "#a7f3d0"];
    return colors[Math.min(index, colors.length - 1)];
  };

  return (
    <g className="target-lines">
      {targets.map((target, i) => {
        const y = priceToY(target, priceRange, imageHeight);
        if (y < 0 || y > imageHeight) return null;

        const color = getTargetColor(i);
        const label = `TP${i + 1}`;

        return (
          <g key={`target-${i}`}>
            {/* Dashed target line */}
            <line
              x1={0}
              y1={y}
              x2={imageWidth}
              y2={y}
              stroke={color}
              strokeWidth="2"
              strokeDasharray="8 4"
              strokeOpacity="0.8"
            />
            {/* Target marker circles */}
            <circle
              cx={imageWidth * 0.3}
              cy={y}
              r="6"
              fill={color}
              fillOpacity="0.9"
            />
            <circle
              cx={imageWidth * 0.6}
              cy={y}
              r="6"
              fill={color}
              fillOpacity="0.9"
            />
            {/* Label with price */}
            <rect
              x={5}
              y={y - fontSize / 2 - 3}
              width={75}
              height={fontSize + 6}
              fill={color}
              fillOpacity="0.95"
              rx="3"
            />
            <text
              x={10}
              y={y}
              fill="white"
              fontSize={fontSize}
              fontWeight="700"
              dominantBaseline="middle"
            >
              {label}
            </text>
            {/* Price label on right side */}
            <rect
              x={imageWidth - 85}
              y={y - fontSize / 2 - 2}
              width={80}
              height={fontSize + 4}
              fill="rgba(0,0,0,0.7)"
              rx="2"
            />
            <text
              x={imageWidth - 10}
              y={y}
              fill={color}
              fontSize={fontSize}
              fontWeight="600"
              fontFamily="monospace"
              textAnchor="end"
              dominantBaseline="middle"
            >
              {target.toFixed(target >= 100 ? 2 : 5)}
            </text>
          </g>
        );
      })}
    </g>
  );
}
