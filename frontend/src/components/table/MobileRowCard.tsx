import { ReactNode } from "react";
import { Card, CardBody } from "../ui/Card";
import { cn } from "../../lib/cn";

export interface MobileRowField {
  label: ReactNode;
  value: ReactNode;
}

export interface MobileRowCardProps {
  title: ReactNode;
  subtitle?: ReactNode;
  meta?: ReactNode;
  fields?: MobileRowField[];
  actions?: ReactNode;
  selectedControl?: ReactNode;
  onClick?: () => void;
  className?: string;
}

export function MobileRowCard({
  title,
  subtitle,
  meta,
  fields = [],
  actions,
  selectedControl,
  onClick,
  className,
}: MobileRowCardProps) {
  return (
    <Card
      className={cn(
        "overflow-hidden",
        onClick ? "cursor-pointer active:bg-slate-50" : "",
        className,
      )}
      onClick={onClick}
    >
      <CardBody className="space-y-4">
        <div className="flex items-start gap-3">
          {selectedControl && <div className="pt-0.5">{selectedControl}</div>}
          <div className="min-w-0 flex-1">
            <div className="break-words text-sm font-semibold text-slate-900">
              {title}
            </div>
            {subtitle && (
              <div className="mt-1 text-sm text-slate-500">{subtitle}</div>
            )}
          </div>
          {meta && (
            <div className="shrink-0 text-right text-xs text-slate-500">
              {meta}
            </div>
          )}
        </div>
        {fields.length > 0 && (
          <dl className="grid grid-cols-1 gap-3 xs:grid-cols-2">
            {fields.map((field, index) => (
              <div key={index} className="min-w-0">
                <dt className="text-xs font-medium uppercase tracking-wide text-slate-400">
                  {field.label}
                </dt>
                <dd className="mt-0.5 break-words text-sm text-slate-700">
                  {field.value}
                </dd>
              </div>
            ))}
          </dl>
        )}
        {actions && (
          <div className="flex flex-col gap-2 border-t border-slate-100 pt-3 xs:flex-row xs:flex-wrap">
            {actions}
          </div>
        )}
      </CardBody>
    </Card>
  );
}
