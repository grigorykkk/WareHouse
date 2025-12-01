using System;

namespace WarehouseSystem;

public class Product
{
    private int _id;
    private int _supplierId;
    private string _name = string.Empty;
    private double _unitVolume;
    private decimal _unitPrice;
    private int _shelfLifeDays;
    private bool _isDeleted;

    public Product(int id, int supplierId, string name, double unitVolume, decimal unitPrice, int shelfLifeDays)
    {
        Id = id;
        SupplierId = supplierId;
        Name = name;
        UnitVolume = unitVolume;
        UnitPrice = unitPrice;
        ShelfLifeDays = shelfLifeDays;
    }

    public int Id
    {
        get => _id;
        private set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Product id must be positive.");
            }

            _id = value;
        }
    }

    public int SupplierId
    {
        get => _supplierId;
        set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Supplier id must be positive.");
            }

            _supplierId = value;
        }
    }

    public string Name
    {
        get => _name;
        set
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException("Product name must be provided.", nameof(value));
            }

            _name = value;
        }
    }

    public double UnitVolume
    {
        get => _unitVolume;
        set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Unit volume must be positive.");
            }

            _unitVolume = value;
        }
    }

    public decimal UnitPrice
    {
        get => _unitPrice;
        set
        {
            if (value <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Unit price must be positive.");
            }

            _unitPrice = value;
        }
    }

    public int ShelfLifeDays
    {
        get => _shelfLifeDays;
        set
        {
            if (value < 0)
            {
                throw new ArgumentOutOfRangeException(nameof(value), "Shelf life must be non-negative.");
            }

            _shelfLifeDays = value;
        }
    }

    public bool IsDeleted => _isDeleted;

    public void UpdateData(int supplierId, string name, double unitVolume, decimal unitPrice, int shelfLifeDays)
    {
        SupplierId = supplierId;
        Name = name;
        UnitVolume = unitVolume;
        UnitPrice = unitPrice;
        ShelfLifeDays = shelfLifeDays;
    }

    public void MarkAsDeleted()
    {
        _isDeleted = true;
    }

    public string GetShortInfo()
    {
        return $"[{Id}] {Name} | Supplier {SupplierId} | Volume {UnitVolume} | Price {UnitPrice:C} | Shelf life {ShelfLifeDays} days";
    }
}
