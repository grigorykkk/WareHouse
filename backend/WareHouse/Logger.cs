using System;
using System.Collections.Generic;
using System.Globalization;

namespace WarehouseSystem;

public class Logger
{
    private readonly List<string> _entries = new();
    private readonly object _syncRoot = new();

    public void LogMovement(Product product, int quantity, Warehouse? source, Warehouse? destination)
    {
        if (product == null)
        {
            throw new ArgumentNullException(nameof(product));
        }

        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be positive.");
        }

        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        var sourceLabel = source == null ? "Поставка" : $"Склад {source.Id} ({source.Type})";
        var destinationLabel = destination == null ? "Нет назначения" : $"Склад {destination.Id} ({destination.Type})";
        var entry = $"{timestamp}: {product.Name} x{quantity} | {sourceLabel} -> {destinationLabel}";

        lock (_syncRoot)
        {
            _entries.Add(entry);
        }
    }

    public void LogNote(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        var entry = $"{timestamp}: {message}";

        lock (_syncRoot)
        {
            _entries.Add(entry);
        }
    }

    public IReadOnlyCollection<string> GetEntries()
    {
        lock (_syncRoot)
        {
            return _entries.AsReadOnly();
        }
    }
}
